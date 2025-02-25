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
DESTINATION_PATHS=($(jq -r '.destinationPaths[]' "$CONFIG_FILE"))

}

print_help () {
    echo "If you need help using backup utility use -h or --help argument"
}

add_path_to_json() {
    local path="$1"
    local key="$2"

    if [[ -d "$path" ]]; then
        # Find the actual mount point
        local mount_point=$(df --output=target "$path" | tail -n1)

        if [[ -z "$mount_point" ]]; then
            echo "Error: Unable to determine mount point for $path" >&2
            exit 1
        fi

        # Get the UUID of the mount point
        local uuid=$(findmnt -no UUID "$mount_point")

        if [[ -z "$uuid" ]]; then
            echo "Error: Unable to determine UUID for $mount_point" >&2
            exit 1
        fi

        # Check if the entry already exists
        if jq -e --arg p "$path" --arg u "$uuid" ".$key[] | select(.path == \$p and .uuid == \$u)" "$CONFIG_FILE" > /dev/null 2>&1; then
            echo "$path with UUID $uuid is already in $key"
        else
            # Add the new entry
            jq --arg p "$path" --arg u "$uuid" \
                ".$key += [{path: \$p, uuid: \$u}]" "$CONFIG_FILE" > tmp.json && mv tmp.json "$CONFIG_FILE"
            echo "Added $path with UUID $uuid to $key"
        fi
        exit 0
    else
        echo "Error: $path is not a valid directory or does not exist." >&2
        exit 1
    fi
}

compress_folders() {
    TIMESTAMP=$(date +"%Y%m%d-%H%M%S")
    TMP_ARCHIVE="/tmp/BackUp_${TIMESTAMP}"

    # Read compression mode from JSON
    COMPRESS_MODE=$(jq -r '.compressionMode' "$CONFIG_FILE")

    # Extract origin paths and their UUIDs
    ORIGIN_PATHS=($(jq -r '.originPaths[].path' "$CONFIG_FILE"))
    ORIGIN_UUIDS=($(jq -r '.originPaths[].uuid' "$CONFIG_FILE"))

    # Verify that all origin paths are available
    for i in "${!ORIGIN_PATHS[@]}"; do
        local mount_point=$(df --output=target "${ORIGIN_PATHS[i]}" | tail -n1)
        MOUNTED_UUID=$(findmnt -no UUID "$mount_point")

        if [[ -z "$MOUNTED_UUID" || "$MOUNTED_UUID" != "${ORIGIN_UUIDS[i]}" ]]; then
            echo "Error: Origin path ${ORIGIN_PATHS[i]} is unavailable or not mounted." >&2
            exit 1
        fi
    done

    # Determine the archive format
    if [[ "$COMPRESS_MODE" == "tar" ]]; then
        TMP_ARCHIVE+=".tar.gz"
        tar -czf "$TMP_ARCHIVE" -C / -- "${ORIGIN_PATHS[@]}"
    else
        TMP_ARCHIVE+=".zip"
        zip -r "$TMP_ARCHIVE" "${ORIGIN_PATHS[@]}"
    fi

    echo "Folders compressed to $TMP_ARCHIVE"
}

copy_to_destinations() {
    
    # Extract destination paths and their UUIDs
    DEST_PATHS=($(jq -r '.destinationPaths[].path' "$CONFIG_FILE"))
    DEST_UUIDS=($(jq -r '.destinationPaths[].uuid' "$CONFIG_FILE"))

    for i in "${!DEST_PATHS[@]}"; do
        local mount_point=$(df --output=target "${DEST_PATHS[i]}" | tail -n1)
        MOUNTED_UUID=$(findmnt -no UUID "$mount_point")

        if [[ -z "$MOUNTED_UUID" || "$MOUNTED_UUID" != "${DEST_UUIDS[i]}" ]]; then
            echo "Error: Destination path ${DEST_PATHS[i]} is unavailable or not mounted." >&2
        else
            cp "$TMP_ARCHIVE" "${DEST_PATHS[i]}"
            echo "Copied $TMP_ARCHIVE to ${DEST_PATHS[i]}"
        fi
    done
}

remove_excess_backups() {
    # Extract destination paths and number of copies from JSON
    NUMBER_OF_COPIES=$(jq -r '.numberOfCopies' "$CONFIG_FILE")

    for DEST_PATH in "${DEST_PATHS[@]}"; do
        # Check if the destination directory exists
        if [[ -d "$DEST_PATH" ]]; then
            # List all backup files sorted by modification time (oldest first)
            BACKUPS=("$DEST_PATH"/BackUp_[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9][0-9][0-9]*) # Assuming backups start with BackUp_
            BACKUP_COUNT=${#BACKUPS[@]}

            if (( BACKUP_COUNT > NUMBER_OF_COPIES )); then
                # Calculate how many backups to remove
                TO_REMOVE=$(( BACKUP_COUNT - NUMBER_OF_COPIES ))

                # Remove the oldest backups
                echo "Removing $TO_REMOVE oldest backup(s) from $DEST_PATH"
                for ((i=0; i<TO_REMOVE; i++)); do
                    rm -f "${BACKUPS[i]}"
                    echo "Removed ${BACKUPS[i]}"
                done
            else
                echo "No excess backups to remove in $DEST_PATH"
            fi
        else
            echo "Error: Destination path $DEST_PATH does not exist or is not a directory." >&2
        fi
    done
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
