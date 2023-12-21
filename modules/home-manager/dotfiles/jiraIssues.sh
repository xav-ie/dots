#!/usr/bin/env bash
# Get issues directly into variable
issues_raw=$(JIRA_API_TOKEN=ATATT3xFfGF0zHiJKYxZJ-9YOeG79MUiTHpAGr4oUVtOdNshSwFxPjlqTxAlb8UyV9i9u5_J_exzbDPm4MDJ6g92sCKOPgRh-4OuI4eSO-uni2CWA8B1-BNcQC9pibeF_DMG1CMYtFam94L5K2Hqk0ANoTQ85gbwsFPR0Vviffprk7Ynrq2DLpY=93EAD8BA NIXPKGS_ALLOW_UNFREE=1 nix run nixpkgs#jira-cli-go -- issue list -a xavier@outsmartly.com --columns key,priority,updated,status,summary --plain)

# Extract header and data
header=$(echo "$issues_raw" | head -n 1)
data=$(echo "$issues_raw" | tail -n +2)

# Initialize final sorted variable
sorted=""

# Status & Priority Order
statuses=("In Progress" "Selected for Development" "Backlog" "Ready For QA" "In Review" "Done")
priorities=("Highest" "High" "Medium" "Low" "Lowest")

# Nested Loop for sorting
for status in "${statuses[@]}"; do
  sorted_by_status=$(echo -e "$data" | grep -E "$(printf '\t')${status}$(printf '\t')")
  for priority in "${priorities[@]}"; do
    filtered_by_priority=$(echo -e "$sorted_by_status" | grep -E "$(printf '\t')${priority}$(printf '\t')")
    [[ -n $filtered_by_priority ]] && sorted="${sorted}${filtered_by_priority}"$'\n'
  done
done

# Cache listIssues output sorted
issues=$(echo -e "$header\n${sorted}")

# ANSI colors
cyan='\033[36m'
yellow='\033[33m'
green='\033[32m'
red='\033[31m'
purple='\033[35m'
gray='\033[90m'
blue='\033[34m'
white='\033[0m'

awk_script=$(cat <<- EOM
    BEGIN {FS="\t+"}
    NR>1 {
        if (\$4 == "In Progress") color=green;
        else if (\$4 == "Done") color=gray;
        else if (\$4 == "Backlog") color=blue;
        else if (\$4 == "Selected for Development") color=cyan;
        else if (\$4 == "Ready For QA") color=yellow;
        else if (\$4 == "In Review") color=purple;
        else color=white;

        if (\$2 == "Highest") bullet="●";
        else if (\$2 == "High") bullet="◉";
        else if (\$2 == "Medium") bullet="◎";
        else if (\$2 == "Low") bullet="○";
        else if (\$2 == "Lowest") bullet="◌";
        else bullet="•";

        printf("%s%s %s", color, bullet, \$5)
        # reprint the whole line again for fzf preview to parse
        # the \t is so that fzf can delimit the pretty line vs its input
        printf("\t%s%s\n", \$0, white);
    }
EOM
)

fzf_preview=$(cat <<- EOM
    id=\$(echo {} | awk -F'\t' '{print \$2}');
    
    echo {} | awk -F'\t' '{
        # 1 => Summary
        # 2 => ID
        # 3 => Priority
        # 4 => nothing???
        # 5 => Date 
        # 6 => Status
        printf("%s%s%s ", "$cyan", \$2, "$white");
        printf("%s%s%s\\t", "$yellow", \$5, "$white");  
        printf("%s%s%s ", "$green", \$6, "$white");  
        printf("%s%s%s\\n", "$purple", \$3, "$white");
    }'
    
    # Use jira-cli-go to fetch issue details
    JIRA_API_TOKEN=ATATT3xFfGF0zHiJKYxZJ-9YOeG79MUiTHpAGr4oUVtOdNshSwFxPjlqTxAlb8UyV9i9u5_J_exzbDPm4MDJ6g92sCKOPgRh-4OuI4eSO-uni2CWA8B1-BNcQC9pibeF_DMG1CMYtFam94L5K2Hqk0ANoTQ85gbwsFPR0Vviffprk7Ynrq2DLpY=93EAD8BA NIXPKGS_ALLOW_UNFREE=1 nix run nixpkgs#jira-cli-go -- issue view \$id
EOM
)
# Feed into fzf
selected=$(echo "$issues" | \
           awk -v red="$red" -v gray="$gray" -v blue="$blue" -v cyan="$cyan" -v yellow="$yellow" -v purple="$purple" -v white="$white" -v green="$green" "$awk_script" | \
           fzf --ansi \
               --delimiter='\t' \
               --with-nth=1 \
               --preview "$fzf_preview" \
               --preview-window=down:70%:wrap)

# Extract the ID (first column) from the selected line
selected_id=$(echo "$selected" | cut -f2- | awk '{print $1}')

# Output selected ID
echo "Selected ID: $selected_id"
