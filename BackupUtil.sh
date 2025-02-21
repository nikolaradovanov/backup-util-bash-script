#!/bin/bash

# Usage:
#
# backup -args
#
# Arguments
#
# -c [zip, tar, plain] set compression mode:
# zip compress to .zip (default)
# tar compress to .tar.gz
# plain do not compress
#
# -n [number] Set maximum amount of backups
#  
# -d [destination] - Add additional backup destination
# copy the backup there if available
#
# -c [cron expression] - execute backup automaticly by cron expression
#
# -m start backup utility in menu mode
# 
# -f [directory] - add additional directory to backup (default /home)
#

#Zip or tar if needed

#check for previous backups

#Copy backup

#delete previous if needed

FOLDER="/home/$USER/.config/backupUtil"
CONFIG_FILE="$FOLDER/backupUtilConf.json"
MAX_BACKUPS_NUMBER=0
COMPRESS_MODE=""
CRON=""

print_usage() {
    cat << EOF

Usage:

 backup -args

Arguments:

 -r Run the backup utility with defined config

 -c [z|t|p] set compression mode:
   z zip compress to .zip (default)
   t tar compress to .tar.gz
   p plain do not compress

 -n [number] Set maximum amount of backups
  
 -d [destination] - Add additional backup destination
   copy the backup there if available

 -t [cron expression] - execute backup automaticly by cron expression
 
 -f [directory] - add additional directory to backup (default /home)

 -m start backup utility in menu mode

 -v print bacukup utility version

 -h help
EOF
}

create_default_file() {
    touch "$CONFIG_FILE"
    echo '{}' > "$CONFIG_FILE"
    jq --arg home "$HOME" '.numberOfCopies = 1 | .compressionMode = "zip" | .executionTime = "" | .originPaths = [$home] | .destinationPaths = [$home]' "$CONFIG_FILE" > tmp.json && mv tmp.json "$CONFIG_FILE"
}

load_the_config() {

if [ ! -d "$FOLDER" ]; then
    mkdir -p "$FOLDER"
fi

if [ ! -f "$CONFIG_FILE" ]; then
    create_default_file
fi

MAX_BACKUPS_NUMBER=$(jq '.numberOfCopies' "$CONFIG_FILE")
COMPRESS_MODE=$(jq '.compressionMode' "$CONFIG_FILE")
CRON=$(jq '.executionTime' "$CONFIG_FILE")
ORIGIN_PATHS=($(jq -r '.originPaths[]' "$CONFIG_FILE"))
DESTINATION_PATHS=($(jq -r '.destinationPaths[]' "$CONFIG_FILE"))

#echo "ORIGIN_PATHS: ${ORIGIN_PATHS[@]}"
}

print_help () {
    echo "If you need help using backup utility use -h or --help argument"
}

add_path_to_json() {
    local path="$1"
    local key="$2"

    if [[ -d "$path" ]]; then
        # Get the device UUID
        local uuid=$(findmnt -no UUID $path)

        if [[ -z "$uuid" ]]; then
            echo "Error: Unable to determine UUID for $path" >&2
            exit 1
        fi

        #TODO this if does not work
        # Check if the entry already exists
        if jq -e --arg p "$path" --arg u "$uuid" ".$key[] | select(.path == \$p and .uuid == \$u)" "$CONFIG_FILE" > /dev/null 2>&1; then
            echo "$path with UUID $uuid is already in $key"
        else
            # Add the new entry
            jq --arg p "$path" --arg u "$uuid" \
                ".$key += [{path: \$p, uuid: \$u}]" "$CONFIG_FILE" > tmp.json && mv tmp.json "$CONFIG_FILE"
            echo "Added $path with UUID $uuid to $key"
        fi
    else
        echo "Error: $path is not a valid directory or does not exist." >&2
        exit 1
    fi
}

compress_folders() {
    TMP_ARCHIVE="/tmp/backup"
    
    if [[ "$COMPRESS_MODE" == "tar" ]]; then
        TMP_ARCHIVE+=".tar.gz"
        tar -czf "$TMP_ARCHIVE" -C / "${ORIGIN_PATHS[@]}"
    else
        TMP_ARCHIVE+=".zip"
        zip -r "$TMP_ARCHIVE" "${ORIGIN_PATHS[@]}"
    fi
    
    echo "Folders compressed to $TMP_ARCHIVE"
}

copy_to_destinations() {

    #TODO
    echo "add cp logic"
}

remove_excess_backups() {

    #TODO
    echo "Add remove logic"
}

load_the_config

while getopts 'n:d:c:f:mrvh' flag; do
    case "$flag" in
        n) 
            if [[ "$OPTARG" =~ ^[0-9]+$ ]]; then
                jq --argjson number "$OPTARG" '.numberOfCopies = $number' "$CONFIG_FILE" > tmp.json && mv tmp.json "$CONFIG_FILE"
            else
                echo "only integer numbers are accepted with -n argument"
                print_help
            fi
            ;;
        d) 
            add_path_to_json "$OPTARG" "destinationPaths"
            ;;
        c) 
            #TODO Add logic to run backup on based cron input
            ;;
        f) 
            add_path_to_json "$OPTARG" "originPaths"
            ;;
        m) 
            #TODO Create Menu mode
            ;;
        r)
            compress_folders
            copy_to_destinations
            remove_excess_backups
        ;;
        v)
            echo "Backup Utility version: v1.0.0"
        ;;
        h)
            print_usage
        ;;
        \?) 
            print_help
            exit 1
            ;;
    esac
done
