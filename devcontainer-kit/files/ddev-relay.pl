#!/usr/bin/perl
# Runs real `ddev` on the Mac for the Claude sandbox, one allowlisted command at a time.
#
# DDEV can't run inside the dev container: it needs the Docker socket, and with the socket
# Claude could start an unfirewalled container mounting any Mac folder. Instead the container's
# `ddev` shim sends the command here (127.0.0.1, reached as host.docker.internal) with the
# token from its own project's token file, which ensure-ddev.sh writes and docker-compose.yml
# mounts into that container only. The token decides the project; the request never names one.
#
# Allowed: start, stop, restart, describe/status, list, logs, snapshot, import-db, export-db,
# each with a fixed set of flags. Restoring a snapshot or importing a database asks first, in
# a macOS dialog, and takes a snapshot before it runs.
# Never: exec, ssh (the web container mounts .ddev writable, and an exec-host hook planted
# there would run on the Mac at the next start), config, add-on, delete, poweroff, push, pull.
#
# Modes: --serve (ensure-ddev.sh starts it detached), --ping (prints the running version).
# State and audit log: ~/.cache/cps-devcontainer/relay/. macOS's own perl, core modules only.
use strict;
use warnings;
use Cwd qw(abs_path);
use File::Basename qw(dirname);
use IO::Socket::INET;
use POSIX qw(strftime);

our $VERSION = 2;
my $PORT = $ENV{CPS_DDEV_RELAY_PORT} || 20090;
my $STATE = "$ENV{HOME}/.cache/cps-devcontainer/relay";
my $TOKENS = "$STATE/tokens";
my $CONTAINER_ROOT = '/workspace';
my $CONFIRM_TIMEOUT = 120;
my $MAX_ARGS = 32;
my $NAME = qr/^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$/;

$ENV{PATH} = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin";

my $mode = shift @ARGV // '';
if ($mode eq '--ping') {
    my $s = IO::Socket::INET->new(PeerAddr => '127.0.0.1', PeerPort => $PORT, Timeout => 3) or exit 1;
    print $s "CPSRELAY1\nPING\n";
    my $reply = <$s> // '';
    exit 1 unless $reply =~ /^PONG (\d+)/;
    print "$1\n";
    exit 0;
}
die "usage: $0 --serve | --ping\n" unless $mode eq '--serve';
serve();

sub log_line {
    my ($msg) = @_;
    open(my $fh, '>>', "$STATE/relay.log") or return;
    print $fh strftime('%F %T', localtime), " $msg\n";
    close $fh;
}

sub serve {
    my $server = IO::Socket::INET->new(LocalAddr => '127.0.0.1', LocalPort => $PORT, Listen => 16,
                                       ReuseAddr => 1) or die "ddev-relay: cannot listen on 127.0.0.1:$PORT: $!\n";
    if (open(my $pidfile, '>', "$STATE/relay.pid")) {
        print $pidfile "$$\n";
        close $pidfile;
    }
    log_line("relay v$VERSION listening on 127.0.0.1:$PORT");
    $SIG{CHLD} = 'IGNORE';
    while (my $client = $server->accept) {
        my $child = fork;
        if (!defined $child) { close $client; next; }
        if ($child) { close $client; next; }
        close $server;
        handle($client);
        exit 0;
    }
}

sub reply_exit {
    my ($sock, $code, $msg) = @_;
    print $sock "ddev (relay): $msg\n" if defined $msg;
    print $sock "\x1eEXIT $code\n";
    close $sock;
    exit 0;
}

sub read_line {
    my ($sock) = @_;
    my $line = <$sock>;
    return undef unless defined $line && length($line) <= 4096;
    chomp $line;
    return $line;
}

# Constant-time compare, so the token can't be guessed a byte at a time.
sub same {
    my ($left, $right) = @_;
    return 0 unless length($left) == length($right);
    my $diff = 0;
    $diff |= ord(substr($left, $_, 1)) ^ ord(substr($right, $_, 1)) for 0 .. length($left) - 1;
    return $diff == 0;
}

sub slurp {
    my ($path) = @_;
    open(my $fh, '<', $path) or return '';
    local $/;
    my $text = <$fh> // '';
    $text =~ s/\s+\z//;
    return $text;
}

# Returns (project, Mac root) for a token, or () when no project has it.
sub project_for {
    my ($token) = @_;
    return () unless $token =~ /^[0-9a-f]{64}$/;
    opendir(my $dh, $TOKENS) or return ();
    for my $file (readdir $dh) {
        next unless $file =~ /^([A-Za-z0-9_.-]+)\.token$/;
        my $project = $1;
        next unless same(slurp("$TOKENS/$file"), $token);
        my $root = slurp("$TOKENS/$project.root");
        return () unless $root && -d $root;
        return ($project, abs_path($root));
    }
    return ();
}

sub handle {
    my ($sock) = @_;
    $SIG{PIPE} = 'IGNORE';
    $sock->autoflush(1);
    local $SIG{ALRM} = sub { exit 0 };
    alarm 10;
    my $magic = read_line($sock) // '';
    exit 0 unless $magic eq 'CPSRELAY1';
    my $first = read_line($sock) // '';
    if ($first eq 'PING') { print $sock "PONG $VERSION\n"; close $sock; exit 0; }

    my ($project, $root) = project_for($first);
    reply_exit($sock, 1, 'unknown token; reopen the dev container so ensure-ddev.sh can set it up') unless $project;
    my $cwd = read_line($sock) // '';
    my $argc = read_line($sock) // '';
    reply_exit($sock, 2, 'bad request') unless $argc =~ /^\d+$/ && $argc >= 1 && $argc <= $MAX_ARGS;
    my @args;
    for (1 .. $argc) {
        my $arg = read_line($sock);
        reply_exit($sock, 2, 'bad request') unless defined $arg && $arg !~ /[\x00-\x1f]/;
        push @args, $arg;
    }
    alarm 0;

    my $request = join(' ', @args);
    my ($argv, $confirm, $error) = plan($project, $root, $cwd, @args);
    if ($error) {
        log_line("$project DENIED  ddev $request  ($error)");
        reply_exit($sock, 2, $error);
    }
    if ($confirm) {
        unless (confirmed($project, $confirm)) {
            log_line("$project REFUSED ddev $request  (not allowed in the dialog)");
            reply_exit($sock, 3, 'not allowed: you clicked Deny on the Mac, or the dialog timed out');
        }
        log_line("$project ALLOWED ddev $request  (in the dialog)");
        my $snap = 'relay-before-' . $args[0] . '-' . strftime('%Y%m%d-%H%M%S', localtime);
        print $sock "ddev (relay): taking snapshot $snap first\n";
        if (run($sock, $root, 'ddev', 'snapshot', '--name', $snap) != 0) {
            log_line("$project FAILED  ddev $request  (safety snapshot failed)");
            reply_exit($sock, 1, 'the safety snapshot failed, so nothing was changed');
        }
    }
    log_line("$project RUN     ddev $request");
    my $code = run($sock, $root, @$argv);
    log_line("$project EXIT $code  ddev $request");
    reply_exit($sock, $code);
}

# Maps a container path to the Mac. Relative paths are relative to the caller's directory.
sub mac_path {
    my ($root, $cwd, $path) = @_;
    $cwd = $CONTAINER_ROOT unless $cwd =~ m{^\Q$CONTAINER_ROOT\E(/|$)};
    $path = "$cwd/$path" unless $path =~ m{^/};
    return undef unless $path =~ m{^\Q$CONTAINER_ROOT\E(/.*)$};
    my $rest = $1;
    return undef if $rest =~ m{(^|/)\.\.(/|$)};
    return "$root$rest";
}

sub inside {
    my ($root, $real) = @_;
    return defined $real && index($real, "$root/") == 0;
}

# Validates one request. Returns (argv, confirmation text or undef, error or undef).
sub plan {
    my ($project, $root, $cwd, $verb, @rest) = @_;
    my $no_args = sub { @rest ? (undef, undef, "ddev $verb takes no arguments here") : (['ddev', $verb], undef, undef) };

    return $no_args->() if $verb =~ /^(start|stop|restart)$/;

    if ($verb eq 'describe' || $verb eq 'status' || $verb eq 'list') {
        my @flags = grep { $_ eq '-j' || $_ eq '--json-output' } @rest;
        return (undef, undef, "ddev $verb accepts only -j here") if @flags != @rest;
        return (['ddev', $verb eq 'status' ? 'describe' : $verb, @flags], undef, undef);
    }

    if ($verb eq 'logs') {
        my @out = ('ddev', 'logs');
        while (defined(my $arg = shift @rest)) {
            if ($arg eq '-t' || $arg eq '--time') { push @out, $arg; next; }
            if ($arg =~ /^--tail=(\d{1,6})$/) { push @out, $arg; next; }
            if ($arg eq '--tail' && ($rest[0] // '') =~ /^\d{1,6}$/) { push @out, $arg, shift @rest; next; }
            if ($arg =~ /^--service=([a-z0-9-]{1,40})$/) { push @out, $arg; next; }
            if (($arg eq '-s' || $arg eq '--service') && ($rest[0] // '') =~ /^[a-z0-9-]{1,40}$/) {
                push @out, $arg, shift @rest; next;
            }
            return (undef, undef, "ddev logs: '$arg' is not allowed here (no -f: the relay can't hold a stream)");
        }
        return (\@out, undef, undef);
    }

    if ($verb eq 'snapshot') {
        return (['ddev', 'snapshot'], undef, undef) unless @rest;
        return (['ddev', 'snapshot', '--list'], undef, undef) if "@rest" =~ /^(--list|-l)$/;
        if (@rest == 2 && $rest[0] eq '--name' && $rest[1] =~ $NAME) {
            return (['ddev', 'snapshot', '--name', $rest[1]], undef, undef);
        }
        if (@rest == 1 && $rest[0] =~ /^--name=(.+)$/ && $1 =~ $NAME) {
            return (['ddev', 'snapshot', '--name', $1], undef, undef);
        }
        if ($rest[0] eq 'restore' && @rest == 2 && ($rest[1] eq '--latest' || $rest[1] =~ $NAME)) {
            return (['ddev', 'snapshot', 'restore', $rest[1]],
                    "Restore DDEV snapshot '$rest[1]' over the $project database?", undef);
        }
        return (undef, undef, 'ddev snapshot: allowed are no arguments, --list, --name NAME, restore NAME|--latest');
    }

    if ($verb eq 'import-db' || $verb eq 'export-db') {
        my ($file, $database, @flags);
        while (defined(my $arg = shift @rest)) {
            if ($arg =~ /^--file=(.+)$/) { $file = $1; next; }
            if (($arg eq '-f' || $arg eq '--file') && defined $rest[0]) { $file = shift @rest; next; }
            if ($arg =~ /^--database=(.+)$/) { $database = $1; next; }
            if (($arg eq '-d' || $arg eq '--database') && defined $rest[0]) { $database = shift @rest; next; }
            if ($verb eq 'import-db' && ($arg eq '--no-drop' || $arg eq '--no-progress')) { push @flags, $arg; next; }
            # A bare --gzip is DDEV's default spelled out; pass it on as --gzip=true.
            if ($verb eq 'export-db' && $arg eq '--gzip') { push @flags, '--gzip=true'; next; }
            if ($verb eq 'export-db' && $arg =~ /^--gzip=(true|false)$/) { push @flags, $arg; next; }
            return (undef, undef, "ddev $verb: '$arg' is not allowed here");
        }
        return (undef, undef, "ddev $verb needs --file=PATH (a file inside the project)") unless defined $file;
        return (undef, undef, "ddev $verb: bad database name") if defined $database && $database !~ $NAME;
        push @flags, "--database=$database" if defined $database;

        my $mac = mac_path($root, $cwd, $file);
        return (undef, undef, "ddev $verb: the file must be inside /workspace") unless defined $mac;

        if ($verb eq 'import-db') {
            my $real = abs_path($mac);
            return (undef, undef, "ddev import-db: $file not found inside the project")
                unless inside($root, $real) && -f $real;
            my $what = defined $database ? "database '$database'" : 'the database';
            return (['ddev', 'import-db', "--file=$real", @flags],
                    "Import $file into $what of $project? It replaces what is there now.", undef);
        }

        # Export writes a new file on the Mac, so it can't replace anything, follow a symlink out,
        # or land in a dot folder (.git, .ddev, .claude, .devcontainer: the sandbox's guardrails).
        return (undef, undef, 'ddev export-db: the file must end in .sql or .sql.gz')
            unless $mac =~ /\.sql(\.gz)?$/;
        my $rel = substr($mac, length $root);
        return (undef, undef, 'ddev export-db: not into a dot folder') if $rel =~ m{/\.};
        return (undef, undef, "ddev export-db: $file already exists; pick a new name") if -e $mac || -l $mac;
        my $parent = abs_path(dirname($mac));
        return (undef, undef, 'ddev export-db: the folder must exist inside the project')
            unless defined $parent && ($parent eq $root || inside($root, $parent)) && -d $parent;
        my $gz = grep { $_ eq '--gzip=false' } @flags;
        push @flags, '--gzip=false' if !$gz && $mac !~ /\.gz$/;
        return (['ddev', 'export-db', "--file=$mac", @flags], undef, undef);
    }

    return (undef, undef, "ddev $verb is not allowed from the sandbox; run it in a terminal on the Mac");
}

sub confirmed {
    my ($project, $text) = @_;
    my @script = ('on run argv',
                  'display dialog (item 1 of argv) with title "DDEV request from the Claude sandbox" '
                  . 'buttons {"Deny", "Allow"} default button "Deny" cancel button "Deny" '
                  . "giving up after $CONFIRM_TIMEOUT with icon caution",
                  'end run');
    my $msg = "$text\n\nA snapshot is taken first. Asked by the dev container for $project.";
    open(my $osa, '-|', 'osascript', (map { ('-e', $_) } @script), $msg) or return 0;
    my $answer = do { local $/; <$osa> } // '';
    close $osa;
    return $answer =~ /button returned:Allow/ && $answer !~ /gave up:true/;
}

# Runs a command in the project's folder, streaming its output to the socket.
sub run {
    my ($sock, $root, @cmd) = @_;
    local $SIG{CHLD} = q{DEFAULT};
    my $pid = open(my $out, q{-|});
    return 1 unless defined $pid;
    if (!$pid) {
        open(STDERR, '>&', \*STDOUT);
        open(STDIN, '<', '/dev/null');
        chdir $root or exit 1;
        exec { $cmd[0] } @cmd or exit 127;
    }
    while (my $line = <$out>) { print $sock $line; }
    close $out;
    return $? >> 8;
}
