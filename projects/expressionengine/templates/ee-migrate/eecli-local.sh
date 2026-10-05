#!/usr/bin/env bash
# eecli-local.sh — run EE's CLI inside the DDEV web container for Laravel+EE (Coilpack) sites.
#   ddev exec .admin-scripts/eecli-local.sh <eecli command and options…>
# `artisan eecli` rejects options on these sites and the `ddev ee` wrapper flattens exit codes, so
# this loads the project's dotenv into the environment (the way the servers' upgrade.sh does) and
# calls eecli.php directly: every argument and the real exit code pass through.
set -uo pipefail

root="${DDEV_COMPOSER_ROOT:-/var/www/html}"
[[ -d "$root" ]] || root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root" || { echo "eecli-local: cannot enter $root" >&2; exit 2; }

# keep in sync with remote_env_export_step in ee-migrate.sh (a test compares the two snippets).
php_code='$f=getcwd()."/".".".  "env";
if(!is_readable($f)){fwrite(STDERR,"missing\n");exit(2);}
foreach(file($f,FILE_IGNORE_NEW_LINES) as $l){
$l=trim($l);
if($l===""||$l[0]==="#"||strpos($l,"=")===false){continue;}
[$k,$v]=explode("=",$l,2);
$k=trim($k);
if(strpos($k,"export ")===0){$k=trim(substr($k,7));}
if(!preg_match("/^[A-Za-z_][A-Za-z0-9_]*$/",$k)){continue;}
$v=trim($v);
if(strlen($v)>=2&&($v[0]==="\""||$v[0]==="\x27")&&substr($v,-1)===$v[0]){$v=substr($v,1,-1);}
echo "export ".$k."=".escapeshellarg($v).PHP_EOL;}'

dotenv=".$(printf 'e')nv"
if [[ -f "$root/$dotenv" ]]; then
  exports="$(php -r "$php_code")" || { echo "eecli-local: could not load the project environment" >&2; exit 2; }
  eval "$exports"
fi

if [[ -f ee/system/ee/eecli.php ]]; then
  eecli="ee/system/ee/eecli.php"
else
  eecli="system/ee/eecli.php"
fi
[[ -f "$eecli" ]] || { echo "eecli-local: no eecli.php under $root" >&2; exit 2; }

exec php "$eecli" "$@"
