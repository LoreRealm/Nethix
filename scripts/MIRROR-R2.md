# Nethix binhost → Cloudflare R2 mirror
#
# Setup (one time):
#   1. Cloudflare dashboard → R2 → Create bucket: nethix-binhost
#   2. R2 → Manage R2 API tokens → Create API token
#      - Object Read & Write, scope: your bucket only
#   3. Copy the Access Key ID / Secret / Endpoint into the config below
#
#   rclone config create nethix-binhost s3 \n#     type=s3 provider=Cloudflare \n#     access_key_id=PASTE \n#     secret_access_key=PASTE \n#     endpoint=https://ACCOUNT_ID.r2.cloudflarestorage.com
#
#   Test:      rclone lsd nethix-binhost:
#   Publish:   rclone sync binhost/ nethix-binhost: --progress
#
# Then make the bucket PUBLIC (R2 bucket → Settings → Public access →
# enable r2.dev or custom domain). The public URL becomes the client's
# PORTAGE_BINHOST, e.g. https://pub-xxxx.r2.dev/ or
# https://binhost.nethix.example.com/
#
# Client side (installed Nethix system) — /etc/portage/binrepos.conf:
#   [nethix-binhost]
#   sync-uri = https://binhost.nethix.example.com/
# and in make.conf:
#   FEATURES="\$FEATURES getbinpkg"
# emerge --usepkg --getbinpkg <pkg> then installs from the mirror.
#
# Nightly refresh (cron): harvest on this machine, then sync:
#   42 3 * * * root /path/to/Nethix/scripts/harvest-binhost.sh && rclone sync /path/to/Nethix/binhost nethix-binhost: --quiet
