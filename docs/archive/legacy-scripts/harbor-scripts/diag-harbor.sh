#!/bin/bash
echo "########## HOST: $(hostname)  ($(hostname -I 2>/dev/null | awk '{print $1}')) ##########"

echo "--- [1] /etc/hosts harbor entry"
grep -i harbor /etc/hosts || echo "(none)"

echo "--- [2] resolve harbor.yjscloud.local"
getent hosts harbor.yjscloud.local || echo "(RESOLVE FAILED)"

echo "--- [3] curl HTTP  http://harbor.yjscloud.local/v2/"
curl -s -o /dev/null -w 'HTTP  code=%{http_code} connect=%{time_connect}s total=%{time_total}s\n' --connect-timeout 8 http://harbor.yjscloud.local/v2/ || echo "HTTP curl FAILED"

echo "--- [4] curl HTTPS https://harbor.yjscloud.local/v2/ (insecure)"
curl -sk -o /dev/null -w 'HTTPS code=%{http_code} connect=%{time_connect}s total=%{time_total}s\n' --connect-timeout 8 https://harbor.yjscloud.local/v2/ || echo "HTTPS curl FAILED"

echo "--- [5] containerd config_path"
grep -n "config_path" /etc/containerd/config.toml || echo "(!!) config_path NOT SET"

echo "--- [6] certs.d tree"
if [ -d /etc/containerd/certs.d ]; then
  for d in /etc/containerd/certs.d/*/; do
    echo "### ${d}"
    cat "${d}hosts.toml" 2>/dev/null
  done
else
  echo "(!!) /etc/containerd/certs.d does not exist"
fi

echo "--- [7] containerd version"
containerd --version 2>/dev/null | head -1

echo "--- [8] DNS poisoning check (registry-1.docker.io)"
getent hosts registry-1.docker.io || echo "(resolve FAILED)"

echo "--- [9] direct docker.io reachability (expect FAIL in CN)"
curl -s -o /dev/null -w 'direct docker.io code=%{http_code}\n' --connect-timeout 6 https://registry-1.docker.io/v2/ 2>&1 || echo "direct docker.io FAILED (expected)"

echo "--- [10] bash-completion present?"
ls -la /usr/share/bash-completion/bash_completion 2>/dev/null || echo "(!!) bash-completion NOT installed"
echo "--- [11] kubectl completion file?"
ls -la /etc/bash_completion.d/kubectl 2>/dev/null || echo "(!!) /etc/bash_completion.d/kubectl missing"

echo "--- [12] crictl/nerdctl present?"
which crictl nerdctl 2>/dev/null || echo "(some tools missing)"

echo "########## END $(hostname) ##########"
