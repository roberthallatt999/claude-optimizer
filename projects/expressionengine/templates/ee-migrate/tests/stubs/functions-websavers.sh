# Stub shared sync library: the three functions the runner may call, plus the dev_* functions
# that must never be called (they log so the tests can assert their absence).
export_db() { echo "export_db $* MYSQL_DEFAULTS_FILE=${MYSQL_DEFAULTS_FILE:-}" >> "$STUB_LOG"; }
download_db() { echo "download_db $*" >> "$STUB_LOG"; }
import_db() {
  echo "import_db $*" >> "$STUB_LOG"
  [[ ! -f "$STUB_DIR/import-fail" ]]
}
dev_upload_db() { echo "dev_upload_db $*" >> "$STUB_LOG"; }
dev_import_db() { echo "dev_import_db $*" >> "$STUB_LOG"; }
dev_export_db() { echo "dev_export_db $*" >> "$STUB_LOG"; }
