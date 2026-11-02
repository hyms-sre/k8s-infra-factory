set -u
P="__PWD__"
H="https://harbor.yjscloud.local"
echo "   repos in dockerhub project:"
curl -sk -u "admin:$P" "$H/api/v2.0/projects/dockerhub/repositories?page_size=50" | python3 -c '
import sys, json
try:
    d = json.load(sys.stdin)
    if d:
        for r in d:
            print("     - " + r["name"])
    else:
        print("     (none)")
except Exception:
    print("     (none)")'
echo "   repos in gcr project:"
curl -sk -u "admin:$P" "$H/api/v2.0/projects/gcr/repositories?page_size=50" | python3 -c '
import sys, json
try:
    d = json.load(sys.stdin)
    if d:
        for r in d:
            print("     - " + r["name"])
    else:
        print("     (none)")
except Exception:
    print("     (none)")'
echo "   registry storage size:"
sudo du -sh /var/lib/longhorn/registry 2>/dev/null | sed 's/^/     /'
echo "   redis/nginx dirs in registry storage:"
sudo find /var/lib/longhorn/registry -type d \( -name redis -o -name nginx \) 2>/dev/null | head -5 | sed 's/^/     /'
