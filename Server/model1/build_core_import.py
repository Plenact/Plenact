#!/usr/bin/env python3
# --------------------------------------------------------------------------------------------------
# @file       build_core_import.py
# @brief      Produce a deterministic staging import with its source-checksum ledger entry
# --------------------------------------------------------------------------------------------------
import hashlib
from pathlib import Path


# @fcn build_import
# @brief Combine reviewed core DDL with its exact source fingerprint, without connecting to a server.
def build_import() -> str:
    source = Path(__file__).with_name('migrations') / '001_core.sql'
    data = source.read_bytes()
    digest = hashlib.sha256(data).hexdigest()
    return data.decode('utf-8') + f"""
-- Record only after every preceding DDL statement has succeeded. Stop on any import error.
INSERT INTO `justirl2_plenact_m1_stage`.`m1_schema_migrations` (migration_id, source_sha256, applied_at_utc, applied_by)
VALUES ('001_core', '{digest}', UTC_TIMESTAMP(6), CURRENT_USER());

SELECT migration_id, source_sha256, applied_at_utc FROM `justirl2_plenact_m1_stage`.`m1_schema_migrations`;
SELECT TABLE_NAME, ENGINE, TABLE_COLLATION FROM information_schema.TABLES
WHERE TABLE_SCHEMA = 'justirl2_plenact_m1_stage' ORDER BY TABLE_NAME;
"""


if __name__ == '__main__':
    target = Path(__file__).with_name('migrations') / '001_core_import_qualified.sql'
    target.write_text(build_import(), encoding='utf-8')
    print(f'Prepared {target.name}; no database connection or deployment performed.')
