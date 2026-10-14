#!/bin/bash

enviroment=$1
case $enviroment in
    dev)
        echo "load Devolpment configurations..."
        config_file="dev.env"
    ;;
    qc)
        echo "load QC configurations..."
        config_file="qc.env"
    ;;
    prod)
        echo "load Production configurations..."
        config_file="prod.env"
    ;;
    *)
        echo "Error: UNKNOWN env."
        echo "Enviroments: dev | qc | prod"
    exit 1
    ;;
esac

config_path="$(dirname "${BASH_SOURCE[0]}")/../config/$config_file"

source "$config_path"
source "$(dirname "${BASH_SOURCE[0]}")/network.sh"

echo "-----------------------------------------------------------------------------------------"
echo "Configuration deployed successfully."



