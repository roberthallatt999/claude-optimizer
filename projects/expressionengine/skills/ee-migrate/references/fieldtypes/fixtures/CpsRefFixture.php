<?php

/**
 * Shared helpers for the fieldtype reference fixtures (references/fieldtypes/fixtures/).
 *
 * Plain class, no EE base class. run-fixtures.sh copies this file next to the fixture in the site's
 * migrations folder; each fixture does require_once __DIR__ . '/CpsRefFixture.php'.
 *
 * Everything the fixtures create is named cpsref_* and resolved by name, so removeAll() can clean up
 * after a half-failed up() and is safe to call twice. Content is written only through the Model service
 * (ChannelEntry + field_id_N), the same path the control panel uses, and read back from the data tables.
 */
class CpsRefFixture
{
    const PREFIX = 'cpsref';
    const CHANNEL = 'cpsref_fixture';
    const GROUP = 'cpsref_fixture';

    private static $booted = false;

    /** Load the legacy field APIs that Grid and fieldtype settings need. Safe to call repeatedly. */
    public static function bootstrap(): void
    {
        if (self::$booted) {
            return;
        }
        ee()->load->library('api');
        ee()->legacy_api->instantiate('channel_fields');
        ee()->api_channel_fields->fetch_installed_fieldtypes();
        ee()->load->model('grid_model');
        self::$booted = true;
    }

    public static function siteId(): int
    {
        return (int) ee()->config->item('site_id');
    }

    /** Create the cpsref_fixture field group (short_name only where the schema has it) and channel; return both. */
    public static function createContainer(): array
    {
        self::bootstrap();

        $group = ee('Model')->make('ChannelFieldGroup');
        $group->site_id = self::siteId();
        $group->group_name = self::GROUP;
        if (ee()->db->field_exists('short_name', 'field_groups')) {
            $group->short_name = self::GROUP;
        }
        $group->save();

        $channel = ee('Model')->make('Channel');
        $channel->site_id = self::siteId();
        $channel->channel_name = self::CHANNEL;
        $channel->channel_title = 'CPS reference fixture';
        $channel->channel_url = '';
        $channel->channel_lang = 'en';
        $channel->deft_status = 'open';
        $channel->save();
        $channel->FieldGroups = $group;
        $channel->save();

        return ['group' => $group, 'channel' => $channel];
    }

    /**
     * Create a top-level channel field attached to $group (pass null to leave it unattached).
     * $settings is the full field_settings array (include field_fmt etc. the fieldtype expects).
     */
    public static function makeField($group, string $name, string $type, array $settings, int $order = 1, array $native = [])
    {
        $field = ee('Model')->make('ChannelField');
        $field->site_id = self::siteId();
        $field->field_name = $name;
        $field->field_label = $name;
        $field->field_type = $type;
        $field->field_instructions = '';
        $field->field_required = 'n';
        $field->field_search = 'n';
        $field->field_is_hidden = 'n';
        $field->field_order = $order;
        $field->legacy_field_data = 'n';
        $field->field_settings = $settings;
        // $native: values for real exp_channel_fields columns (field_maxl, field_text_direction, field_fmt,
        // field_ta_rows, field_content_type, ...). Optional; added for text/textarea (Plan 2 Task 2).
        foreach ($native as $property => $value) {
            $field->$property = $value;
        }
        if ($group) {
            $field->ChannelFieldGroups = $group;
        }
        $field->save();

        return $field;
    }

    /**
     * Create a Grid field and its columns. $columns is a list of
     * ['name' => col_name, 'type' => col_type, 'label' => ..., 'settings' => array].
     * Returns the ChannelField; read column ids back with gridColumnId().
     */
    public static function makeGridField($group, string $name, array $columns, int $order = 2)
    {
        self::bootstrap();

        $grid = self::makeField($group, $name, 'grid', [
            'grid_min_rows' => 0, 'grid_max_rows' => '', 'allow_reorder' => 'y',
            'vertical_layout' => 'n', 'row_counter' => 'n',
        ], $order);

        ee()->grid_model->create_field($grid->field_id, 'channel');
        foreach (array_values($columns) as $index => $column) {
            // field_id and content_type go INSIDE the array; positional args leave orphan columns.
            ee()->grid_model->save_col_settings([
                'field_id' => $grid->field_id,
                'content_type' => 'channel',
                'col_order' => $index,
                'col_type' => $column['type'],
                'col_label' => $column['label'] ?? $column['name'],
                'col_name' => $column['name'],
                'col_instructions' => '',
                'col_required' => 'n',
                'col_search' => 'n',
                'col_width' => 0,
                'col_settings' => json_encode($column['settings'] ?? []),
            ], false, 'channel');
        }

        return $grid;
    }

    /** Create a Fluid field whose allowed children are the given field names. */
    public static function makeFluidField($group, string $name, array $childFieldNames, int $order = 3)
    {
        $ids = array_map([self::class, 'fieldId'], $childFieldNames);

        return self::makeField($group, $name, 'fluid_field', [
            'field_channel_fields' => $ids,
            'field_channel_field_groups' => [],
        ], $order);
    }

    /**
     * Create one entry in cpsref_fixture. $values maps field_name => value, where value is whatever the
     * fieldtype's save() expects (string; Grid ['rows' => ['new_row_1' => ['col_id_N' => v]]];
     * Fluid ['fields' => ['new_field_1' => ['field_id_N' => v]]]). Returns the entry id.
     */
    public static function makeEntry(string $urlTitle, array $values): int
    {
        self::bootstrap();

        $channel = ee('Model')->get('Channel')->filter('channel_name', self::CHANNEL)->first();
        $entry = ee('Model')->make('ChannelEntry');
        $entry->Channel = $channel;
        $entry->site_id = self::siteId();
        $entry->author_id = self::authorId();
        $entry->title = $urlTitle;
        $entry->url_title = $urlTitle;
        $entry->status = 'open';
        $entry->entry_date = ee()->localize->now;
        foreach ($values as $fieldName => $value) {
            $property = 'field_id_' . self::fieldId($fieldName);
            $entry->$property = $value;
        }
        $entry->save();

        return (int) $entry->entry_id;
    }

    /** Lowest existing member id; member 1 does not exist on every site (it is absent on local cps). */
    public static function authorId(): int
    {
        $row = ee()->db->select_min('member_id', 'id')->get('members')->row_array();

        return (int) ($row['id'] ?? 0);
    }

    public static function fieldId(string $name): int
    {
        $row = ee()->db->select('field_id')->where('field_name', $name)->get('channel_fields')->row_array();

        return (int) ($row['field_id'] ?? 0);
    }

    public static function gridColumnId(string $fieldName, string $colName): int
    {
        // Resolve the id first: a query inside a pending active-record chain corrupts the chain.
        $fieldId = self::fieldId($fieldName);
        $row = ee()->db->select('col_id')->where('field_id', $fieldId)
            ->where('col_name', $colName)->get('grid_columns')->row_array();

        return (int) ($row['col_id'] ?? 0);
    }

    public static function entryId(string $urlTitle): int
    {
        $row = ee()->db->select('entry_id')->where('url_title', $urlTitle)->get('channel_titles')->row_array();

        return (int) ($row['entry_id'] ?? 0);
    }

    /** Decoded channel_fields.field_settings (base64-serialized). Empty array when the field is missing. */
    public static function fieldSettings(string $fieldName): array
    {
        $row = ee()->db->select('field_settings')->where('field_name', $fieldName)
            ->get('channel_fields')->row_array();
        $decoded = isset($row['field_settings']) ? unserialize(base64_decode($row['field_settings'])) : [];

        return is_array($decoded) ? $decoded : [];
    }

    /** Decoded grid_columns.col_settings (JSON). Empty array when the column is missing. */
    public static function gridColumnSettings(string $fieldName, string $colName): array
    {
        $fieldId = self::fieldId($fieldName);
        $row = ee()->db->select('col_settings')->where('field_id', $fieldId)
            ->where('col_name', $colName)->get('grid_columns')->row_array();
        $decoded = isset($row['col_settings']) ? json_decode($row['col_settings'], true) : [];

        return is_array($decoded) ? $decoded : [];
    }

    /** Raw value of a top-level field for an entry, read from channel_data_field_N. null when absent. */
    public static function fieldValue(string $fieldName, int $entryId): ?string
    {
        $fieldId = self::fieldId($fieldName);
        $table = ee()->db->dbprefix . 'channel_data_field_' . $fieldId;
        $row = ee()->db->query(
            'SELECT `field_id_' . $fieldId . '` AS v FROM `' . $table . '` WHERE entry_id = ' . (int) $entryId
        )->row_array();

        return $row['v'] ?? null;
    }

    /** All rows of a Grid field for an entry (arrays keyed col_id_N), in row order. */
    public static function gridRows(string $fieldName, int $entryId): array
    {
        $table = ee()->db->dbprefix . 'channel_grid_field_' . self::fieldId($fieldName);

        return ee()->db->query(
            'SELECT * FROM `' . $table . '` WHERE entry_id = ' . (int) $entryId . ' ORDER BY row_order'
        )->result_array();
    }

    /** Fluid rows (fluid_field_data) for an entry and fluid field, in order. */
    public static function fluidRows(string $fluidFieldName, int $entryId): array
    {
        $fluidFieldId = self::fieldId($fluidFieldName);

        return ee()->db->where('fluid_field_id', $fluidFieldId)
            ->where('entry_id', $entryId)->order_by('order')->get('fluid_field_data')->result_array();
    }

    /** Whether a table exists (SHOW TABLES, not list_fields: EE caches table_exists per request). */
    public static function tableExists(string $unprefixed): bool
    {
        $name = ee()->db->dbprefix . $unprefixed;

        return ee()->db->query('SHOW TABLES LIKE ' . ee()->db->escape($name))->num_rows() > 0;
    }

    /** Whether a column exists on an (unprefixed) table, via SHOW COLUMNS. */
    public static function columnExists(string $unprefixed, string $column): bool
    {
        if (! self::tableExists($unprefixed)) {
            return false;
        }
        $name = ee()->db->dbprefix . $unprefixed;

        return ee()->db->query(
            'SHOW COLUMNS FROM `' . $name . '` LIKE ' . ee()->db->escape($column)
        )->num_rows() > 0;
    }

    /**
     * SQL type string of a column on an (unprefixed) table, from SHOW COLUMNS (e.g. 'text', 'int(11)',
     * 'decimal(10,4)'); null when the table or column is missing. Lower-cased.
     */
    public static function columnType(string $unprefixed, string $column): ?string
    {
        if (! self::tableExists($unprefixed)) {
            return null;
        }
        $row = ee()->db->query(
            'SHOW COLUMNS FROM `' . ee()->db->dbprefix . $unprefixed . '` LIKE ' . ee()->db->escape($column)
        )->row_array();

        return isset($row['Type']) ? strtolower($row['Type']) : null;
    }

    /** Column value of a native exp_channel_fields column for a field name; null when missing. */
    public static function nativeColumn(string $fieldName, string $column)
    {
        $row = ee()->db->select($column)->where('field_name', $fieldName)->get('channel_fields')->row_array();

        return $row[$column] ?? null;
    }

    /** Append $message to $problems when $condition is false (verify() collects failures this way). */
    public static function check(array &$problems, bool $condition, string $message): void
    {
        if (! $condition) {
            $problems[] = $message;
        }
    }

    /**
     * Remove everything named cpsref*: entries, channel, fields (Fluid and Grid first, children last),
     * grid columns, field group. Idempotent; call from down() and from a failed up().
     */
    public static function removeAll(): void
    {
        self::bootstrap();

        $channels = ee('Model')->get('Channel')->filter('channel_name', 'LIKE', self::PREFIX . '%')->all();
        foreach ($channels as $channel) {
            $entries = ee('Model')->get('ChannelEntry')->filter('channel_id', $channel->channel_id)->all();
            foreach ($entries as $entry) {
                $entry->delete();
            }
            $channel->delete();
        }

        // Fluid first (it owns rows in the child fields' data tables), then Grid, then the rest.
        $fields = ee('Model')->get('ChannelField')->filter('field_name', 'LIKE', self::PREFIX . '%')->all();
        $rank = ['fluid_field' => 0, 'grid' => 1, 'file_grid' => 1];
        $sorted = $fields->asArray();
        usort($sorted, function ($a, $b) use ($rank) {
            return ($rank[$a->field_type] ?? 2) <=> ($rank[$b->field_type] ?? 2);
        });
        foreach ($sorted as $field) {
            $fieldId = (int) $field->field_id;
            $field->delete();
            ee()->db->where('field_id', $fieldId)->delete('grid_columns');
        }

        $groups = ee('Model')->get('ChannelFieldGroup')->filter('group_name', 'LIKE', self::PREFIX . '%')->all();
        foreach ($groups as $group) {
            $group->delete();
        }
    }
}
