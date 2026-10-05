<?php

use ExpressionEngine\Service\Migration\Migration;

require_once __DIR__ . '/CpsRefFixture.php';

/**
 * Fieldtype reference fixture: notes (Plan 2 Task 2). Notes is display-only: its text lives in the field
 * settings (note_content) and the entry never stores a value. Creates a top-level field, a Grid column and a
 * Fluid child (creation only), saves an entry that carries no notes value, and proves the data column stays
 * NULL. down() removes everything cpsref*.
 */
class CpsrefNotes extends Migration
{
    const FIELD = 'cpsref_notes';
    const GRID = 'cpsref_notes_grid';
    const FLUID = 'cpsref_notes_fluid';
    const COLUMN = 'cpsref_notes_col';
    const ENTRY = 'cpsref-notes';

    public function up()
    {
        try {
            $this->build();
        } catch (\Throwable $e) {
            try {
                CpsRefFixture::removeAll();
            } catch (\Throwable $cleanupError) {
                // Keep the original failure; the cleanup error is secondary.
            }
            throw $e;
        }
    }

    private function build(): void
    {
        $container = CpsRefFixture::createContainer();
        $group = $container['group'];

        // ft.notes.php::save_settings() keeps exactly these three keys (default_settings).
        $settings = [
            'note_content' => "# Fixture note\n\nShown on the publish form; stored in settings, not in the entry.",
            'field_hide_title' => true,
            'field_hide_publish_layout_collapse' => true,
        ];
        CpsRefFixture::makeField($group, self::FIELD, 'notes', $settings, 1);
        CpsRefFixture::makeGridField($group, self::GRID, [
            ['name' => self::COLUMN, 'type' => 'notes', 'label' => 'Notes column', 'settings' => $settings],
        ], 2);
        CpsRefFixture::makeFluidField($group, self::FLUID, [self::FIELD], 3);

        // No notes value: the field has nothing to write.
        CpsRefFixture::makeEntry(self::ENTRY, []);
    }

    public function down()
    {
        CpsRefFixture::removeAll();
    }

    public function verify(): array
    {
        CpsRefFixture::bootstrap();
        $problems = [];
        $contract = ['note_content', 'field_hide_title', 'field_hide_publish_layout_collapse'];

        $field = CpsRefFixture::fieldSettings(self::FIELD);
        $column = CpsRefFixture::gridColumnSettings(self::GRID, self::COLUMN);
        foreach ($contract as $key) {
            CpsRefFixture::check($problems, array_key_exists($key, $field), "field settings missing $key");
            CpsRefFixture::check($problems, array_key_exists($key, $column), "grid column settings missing $key");
        }

        $fieldId = CpsRefFixture::fieldId(self::FIELD);
        $colId = CpsRefFixture::gridColumnId(self::GRID, self::COLUMN);
        $gridId = CpsRefFixture::fieldId(self::GRID);
        // notes has no settings_modify_column override, so it still gets the default text column.
        $type = CpsRefFixture::columnType('channel_data_field_' . $fieldId, 'field_id_' . $fieldId);
        CpsRefFixture::check($problems, $type === 'text', "notes column type is $type, expected text");
        $gridType = CpsRefFixture::columnType('channel_grid_field_' . $gridId, 'col_id_' . $colId);
        CpsRefFixture::check($problems, $gridType === 'text', "grid column type is $gridType, expected text");
        CpsRefFixture::check(
            $problems,
            CpsRefFixture::fluidRows(self::FLUID, CpsRefFixture::entryId(self::ENTRY)) === [],
            'unexpected fluid rows'
        );

        $entryId = CpsRefFixture::entryId(self::ENTRY);
        CpsRefFixture::check($problems, $entryId > 0, 'entry not found');
        // The entry stores nothing for notes: its column is NULL (or the row is absent).
        CpsRefFixture::check(
            $problems,
            CpsRefFixture::fieldValue(self::FIELD, $entryId) === null,
            'notes column holds data; expected NULL'
        );
        CpsRefFixture::check(
            $problems,
            CpsRefFixture::gridRows(self::GRID, $entryId) === [],
            'unexpected grid rows'
        );

        return $problems;
    }
}
