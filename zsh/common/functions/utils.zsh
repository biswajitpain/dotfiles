#!/usr/bin/env zsh

# mkd: Create a new directory and enter it
# Usage: mkd <directory_name>
# Description: Creates a new directory and changes into it.
mkd() {
    mkdir -p "$@" && cd "$_"
}

# gmsg: Short git messages
# Usage: gmsg [commit_message]
# Description: Creates a git commit with a short message. If no message is provided,
# it uses a default message with the current user and timestamp.
gmsg() {
    if [ ! -d .git ]; then
        error "Not a git repository. Please run this command from the root of a git repository."
        return 1
    fi

    if git diff --cached --quiet; then
        error "No staged changes to commit. Use 'git add' to stage changes."
        return 1
    fi

    timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    current_user=$(whoami)

    if [ -n "$1" ]; then
        commit_message="$1"
    else
        commit_message="New git commit from $current_user on $timestamp"
    fi

    git commit -m "$commit_message"

    if [ $? -eq 0 ]; then
        log "Changes committed successfully."
    else
        error "Failed to commit changes."
    fi
}

# ff: Find file/directory from root
# Usage: ff <filename>
# Description: Searches for a file or directory from the root directory.
ff() { find / -name "$1" 2>/dev/null }

# fh: Find file/directory from home
# Usage: fh <filename>
# Description: Searches for a file or directory from the home directory.
fh() { find ~/ -name "$1" 2>/dev/null }

# dataurl: Create a data URL from a file
# Usage: dataurl <file>
# Description: Generates a data URL from the given file.
dataurl() {
    local mimeType=$(file -b --mime-type "$1")
    if [[ $mimeType == text/* ]]; then
        mimeType="${mimeType};charset=utf-8"
    fi
    echo "data:${mimeType};base64,$(openssl base64 -in "$1" | tr -d '\n')"
}

# server: Start an HTTP server from a directory
# Usage: server [port]
# Description: Starts a Python HTTP server in the current directory. Default port is 8000.
server() {
    local port="${1:-8000}"
    python -m SimpleHTTPServer "$port"
}

# weather: Get weather
# Usage: weather [location]
# Description: Fetches and displays weather information for the specified location.
weather() {
    curl -s "wttr.in/$1"
}

# extract: Extract archives
# Usage: extract <archive_file>
# Description: Extracts various types of archive files.
extract() {
    if [ -f $1 ] ; then
        case $1 in
            *.tar.bz2)   tar xjf $1     ;;
            *.tar.gz)    tar xzf $1     ;;
            *.bz2)       bunzip2 $1     ;;
            *.rar)       unrar e $1     ;;
            *.gz)        gunzip $1      ;;
            *.tar)       tar xf $1      ;;
            *.tbz2)      tar xjf $1     ;;
            *.tgz)       tar xzf $1     ;;
            *.zip)       unzip $1       ;;
            *.Z)         uncompress $1  ;;
            *.7z)        7z x $1        ;;
            *)     echo "'$1' cannot be extracted via extract()" ;;
        esac
    else
        echo "'$1' is not a valid file"
    fi
}

# tmpd: Make a temporary directory and enter it
# Usage: tmpd [directory_name]
# Description: Creates a temporary directory and changes into it.
tmpd() {
    local dir
    if [ $# -eq 0 ]; then
        dir=$(mktemp -d)
    else
        dir=$(mktemp -d -t "${1}.XXXXXXXXXX")
    fi
    cd "$dir" || exit
}

# targz: Create a .tar.gz archive
# Usage: targz <directory>
# Description: Creates a compressed tar archive of the specified directory.
targz() {
    local tmpFile="${1%/}.tar"
    tar -cvf "${tmpFile}" --exclude=".DS_Store" "${1}" || return 1

    size=$(
        stat -f"%z" "${tmpFile}" 2> /dev/null; # macOS `stat`
        stat -c"%s" "${tmpFile}" 2> /dev/null;  # GNU `stat`
    )

    local cmd=""
    if (( size < 52428800 )) && hash zopfli 2> /dev/null; then
        cmd="zopfli"
    else
        if hash pigz 2> /dev/null; then
            cmd="pigz"
        else
            cmd="gzip"
        fi
    fi

    echo "Compressing .tar ($((size / 1000)) kB) using \`${cmd}\`…"
    "${cmd}" -v "${tmpFile}" || return 1
    [ -f "${tmpFile}" ] && rm "${tmpFile}"

    zippedSize=$(
        stat -f"%z" "${tmpFile}.gz" 2> /dev/null; # macOS `stat`
        stat -c"%s" "${tmpFile}.gz" 2> /dev/null; # GNU `stat`
    )

    echo "${tmpFile}.gz ($((zippedSize / 1000)) kB) created successfully."
}

# fs: Determine size of a file or total size of a directory
# Usage: fs [file/directory]
# Description: Shows the size of a file or the total size of a directory.
fs() {
    if du -b /dev/null > /dev/null 2>&1; then
        local arg=-sbh;
    else
        local arg=-sh;
    fi
    if [[ -n "$@" ]]; then
        du $arg -- "$@";
    else
        du $arg .[^.]* ./*;
    fi;
}

# digs: Short DNS lookup
# Usage: digs <domain>
# Description: Performs a short DNS lookup, showing only the IP address.
digs() {
    dig +short "$1"
}

# digx: Reverse DNS lookup
# Usage: digx <ip_address>
# Description: Performs a reverse DNS lookup, finding the domain name associated with an IP.
digx() {
    dig -x "$1"
}

# digmx: DNS lookup for MX records
# Usage: digmx <domain>
# Description: Looks up MX (mail exchanger) records for a domain.
digmx() {
    dig "$1" MX +short
}

# digns: DNS lookup for NS records
# Usage: digns <domain>
# Description: Looks up NS (nameserver) records for a domain.
digns() {
    dig "$1" NS +short
}

# diga: DNS lookup for A records
# Usage: diga <domain>
# Description: Looks up A (IPv4 address) records for a domain.
diga() {
    dig "$1" A +short
}

# digaaaa: DNS lookup for AAAA records
# Usage: digaaaa <domain>
# Description: Looks up AAAA (IPv6 address) records for a domain.
digaaaa() {
    dig "$1" AAAA +short
}

# digtxt: DNS lookup for TXT records
# Usage: digtxt <domain>
# Description: Looks up TXT records for a domain.
digtxt() {
    dig "$1" TXT +short
}

# digtrace: Trace DNS path
# Usage: digtrace <domain>
# Description: Traces the path of DNS resolution from root servers.
digtrace() {
    dig +trace "$1"
}

# digprop: Check DNS propagation
# Usage: digprop <domain>
# Description: Checks DNS propagation by querying multiple public DNS servers.
digprop() {
    dig "$1" @8.8.8.8 +short
    dig "$1" @1.1.1.1 +short
    dig "$1" @208.67.222.222 +short
}

# digns: DNS lookup with specific nameserver
# Usage: digns <domain> <nameserver>
# Description: Allows querying a specific nameserver for DNS information.
digns() {
    if [ $# -ne 2 ]; then
        echo "Usage: digns <domain> <nameserver>"
        return 1
    fi
    dig "@$2" "$1"
}

# digga: Run `dig` and display the most useful info
# Usage: digga <domain>
# Description: Performs a DNS lookup and displays the most useful information.
digga() {
    dig +nocmd "$1" any +multiline +noall +answer;
}

# getcertnames: Show all the names listed in the SSL certificate for a given domain
# Usage: getcertnames <domain>
# Description: Retrieves and displays the Common Name and Subject Alternative Names from the SSL certificate of a domain.
getcertnames() {
    if [ -z "${1}" ]; then
        echo "ERROR: No domain specified.";
        return 1;
    fi;

    local domain="${1}";
    echo "Testing ${domain}…";
    echo ""; # newline

    local tmp=$(echo -e "GET / HTTP/1.0\nEOT" \
        | openssl s_client -connect "${domain}:443" -servername "${domain}" 2>&1);

    if [[ "${tmp}" = *"-----BEGIN CERTIFICATE-----"* ]]; then
        local certText=$(echo "${tmp}" \
            | openssl x509 -text -certopt "no_aux, no_header, no_issuer, no_pubkey, \
            no_serial, no_sigdump, no_signame, no_validity, no_version");
        echo "Common Name:";
        echo ""; # newline
        echo "${certText}" | grep "Subject:" | sed -e "s/^.*CN=//" | sed -e "s/\/emailAddress=.*//";
        echo ""; # newline
        echo "Subject Alternative Name(s):";
        echo ""; # newline
        echo "${certText}" | grep -A 1 "Subject Alternative Name:" \
            | sed -e "2s/DNS://g" -e "s/ //g" | tr "," "\n" | tail -n +2;
        return 0;
    else
        echo "ERROR: Certificate not found.";
        return 1;
    fi;
}