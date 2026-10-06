<?php

namespace CPS\Tools\Commands;

use ExpressionEngine\Cli\Cli;

/**
 * Empty this site's EE cache namespace, including the model metadata caches that `cache:clear` leaves.
 *
 * EE caches each field's column names by field id with no expiry (FieldModel::getColumnNames()), under
 * the site's cache namespace. `eecli cache:clear` only deletes the page, tag and database caches, so
 * after the database is swapped for another one (an import, a snapshot restore, a staging reset) EE
 * keeps querying the columns of whichever field used to have that id. This command calls
 * ee()->cache->clean() for the site scope: with the file driver that is system/user/cache/<site>/ only,
 * never the cache root, where database backups live.
 *
 * Changes no database row and no content. Exit code 0 on success, 1 if the cache could not be cleaned.
 */
class CommandCacheClean extends Cli
{
    /**
     * @var string
     */
    public $name = 'CPS Cache Clean';

    /**
     * @var string
     */
    public $signature = 'cps:cache-clean';

    /**
     * @var string
     */
    public $usage = 'php eecli.php cps:cache-clean';

    /**
     * @var string
     */
    public $description = 'Empty this site\'s EE cache namespace, including model metadata that cache:clear keeps.';

    /**
     * @var string
     */
    public $summary = 'Empty the site cache namespace (use after a database swap)';

    /**
     * @var array
     */
    public $commandOptions = [];

    /**
     * Run the command.
     *
     * @return void
     */
    public function handle()
    {
        // Page, tag and database caches first, the same as `cache:clear`.
        ee()->functions->clear_caching('all');

        if (ee()->cache->clean() === false) {
            $this->error('cps:cache-clean: the site cache could not be cleaned');
            exit(1);
        }

        $this->info('cps:cache-clean: site cache namespace emptied');
    }
}
