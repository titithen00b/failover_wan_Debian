#!/bin/bash
vnstat -i "$BACKUP_IF" --oneline | awk -F\; '{print $11}'
