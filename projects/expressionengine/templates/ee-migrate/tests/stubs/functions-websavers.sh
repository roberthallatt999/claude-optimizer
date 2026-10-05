# Stub shared sync library: the three read-only functions the runner may call.
export_db() { echo "export_db $*" >> "$STUB_LOG"; }
download_db() { echo "download_db $*" >> "$STUB_LOG"; }
import_db() { echo "import_db $*" >> "$STUB_LOG"; }
