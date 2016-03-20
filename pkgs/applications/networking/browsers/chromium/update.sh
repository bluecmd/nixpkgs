#!/bin/sh

channels_url="http://omahaproxy.appspot.com/all?csv=1";
history_url="http://omahaproxy.appspot.com/history";
bucket_url="http://commondatastorage.googleapis.com/chromium-browser-official/";
base_path="$(cd "$(dirname "$0")" && pwd)";

source "$(nix-build --no-out-link "$base_path/update.nix" -A updateHelpers)";

### poor mans key/value-store :-) ###

ver_sha_table=""; # list of version:sha256

sha_insert()
{
    version="$1";
    sha256="$2";

    ver_sha_table="$ver_sha_table $version:$sha256";
}

get_newest_ver()
{
    versions="$(for v in $@; do echo "$v"; done)";
    if oldest="$(echo "$versions" | sort -V 2> /dev/null | tail -n1)";
    then
        echo "$oldest";
    else
        echo "$versions" | sort -t. -k 1,1n -k 2,2n -k 3,3n -k 4,4n | tail -n1;
    fi;
}

fetch_filtered_history()
{
    curl -s "$history_url" | sed -nr 's/^'"linux,$1"',([^,]+).*$/\1/p';
}

get_prev_sha256()
{
    channel="$1";
    current_version="$2";

    for version in $(fetch_filtered_history "$channel");
    do
        [ "x$version" = "x$current_version" ] && continue;
        sha256="$(get_sha256 "$channel" "$version")" || continue;
        echo "$sha256:$version";
        return 0;
    done;
}

get_channel_exprs()
{
    for chline in $1;
    do
        channel="${chline%%,*}";
        version="${chline##*,}";

        sha256="$(get_sha256 "$channel" "$version")";
        if [ $? -ne 0 ];
        then
            echo "Whoops, failed to fetch $version, trying previous" \
                 "versions:" >&2;

            sha_ver="$(get_prev_sha256 "$channel" "$version")";
            sha256="${sha_ver%:*}";
            version="${sha_ver#*:}";
        fi;

        sha_insert "$version" "$sha256";

        main="${sha256%%.*}";
        deb="${sha256#*.}";
        deb32="${deb%.*}";
        deb64="${deb#*.}";

        echo "  $channel = {";
        echo "    version = \"$version\";";
        echo "    sha256 = \"$main\";";
        if [ "x${deb#*[a-z0-9].[a-z0-9]}" != "x$deb" ];
        then
            echo "    sha256bin32 = \"$deb32\";";
            echo "    sha256bin64 = \"$deb64\";";
        fi;
        echo "  };";
    done;
}

cd "$(dirname "$0")";

omaha="$(curl -s "$channels_url")";
versions="$(echo "$omaha" | sed -nr -e 's/^linux,([^,]+,[^,]+).*$/\1/p')";
channel_exprs="$(get_channel_exprs "$versions")";

cat > "$base_path/upstream-info.nix" <<-EOF
# This file is autogenerated from update.sh in the parent directory.
{
$channel_exprs
}
EOF
