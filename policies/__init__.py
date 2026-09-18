# Required. Checkov's external-checks loader skips any directory without an __init__.py, and it
# reports that at INFO level — so without this file the checks silently never run and every scan
# looks clean. Do not delete.
