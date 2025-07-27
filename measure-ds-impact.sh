#!/bin/bash

# === CONFIGURATION ===
PACKAGE_SCOPE="@envato/design-system"              # The scoped package name used across repos
COMPONENT_CONFIG="components.json"                # Component list file
TMP_OUTPUT="weekly-impact.json"                   # This week's temp data
LOG_FILE="impact-log.json"                        # Cumulative log
WEEK=$(date +%F)                                   # e.g. "2025-07-20"

# Clean up any existing temp directory
rm -rf temp/
mkdir -p temp/

# === GET LATEST DESIGN SYSTEM VERSION ===
LATEST_VERSION=$(npm view "$PACKAGE_SCOPE" version 2>/dev/null)

if [ -z "$LATEST_VERSION" ]; then
  echo "❌ Could not fetch latest version of $PACKAGE_SCOPE from npm. Exiting."
  exit 1
fi

echo "📦 Latest DS version: $LATEST_VERSION"

# === INIT TEMP OUTPUT ===
echo "[]" > $TMP_OUTPUT

# === READ LIST OF REPOS AND CONFIG FROM FILE ===
cat repos.txt | while read REPO_LINE; do
  REPO_NAME=$(echo $REPO_LINE | cut -d '|' -f1 | xargs)
  SEARCH_PATH=$(echo $REPO_LINE | cut -d '|' -f2 | xargs)
  PACKAGE_NAME=$(echo $REPO_LINE | cut -d '|' -f3 | xargs)

  echo "\n🔍 Checking repo: $REPO_NAME"
  REPO_TEMP_DIR="temp/$(basename $REPO_NAME)"

  # Ensure clean clone directory
  rm -rf "$REPO_TEMP_DIR"
  
  # Clone the repo shallowly
  git clone --depth=1 git@github.com:$REPO_NAME.git "$REPO_TEMP_DIR"

  # Try to find version in multiple possible package.json locations
  VERSION=""
  
  # List of possible package.json locations
  LOCATIONS=(
    "$REPO_TEMP_DIR/package.json"
    "$REPO_TEMP_DIR/$SEARCH_PATH/package.json"
    "$REPO_TEMP_DIR/packages/package.json"
    "$REPO_TEMP_DIR/packages/rails-app/package.json"
    "$REPO_TEMP_DIR/packages/rails-app/app/javascript/package.json"
    "$REPO_TEMP_DIR/packages/elements-marketing-modules/package.json"
  )

  # Try each location until we find a version
  echo "Looking for $PACKAGE_NAME version in possible locations:"
  for loc in "${LOCATIONS[@]}"; do
    if [ -f "$loc" ]; then
      echo "  Checking $loc"
      FOUND_VERSION=$(jq -r ".dependencies[\"$PACKAGE_NAME\"] // .devDependencies[\"$PACKAGE_NAME\"] // empty" "$loc")
      if [ ! -z "$FOUND_VERSION" ]; then
        VERSION=$FOUND_VERSION
        echo "  ✅ Found version $VERSION"
        break
      else
        echo "  ❌ No version found"
      fi
    else
      echo "  ⚠️  File not found: $loc"
    fi
  done

  echo "Final version found: ${VERSION:-none}"

  # === Component-level breakdown ===
  COMPONENTS_FILE="temp/components-$(basename $REPO_NAME).jsonl"
  > $COMPONENTS_FILE

  # Initialize total component count
  TOTAL_COMPONENTS=0

  jq -c '.[]' $COMPONENT_CONFIG | while read COMPONENT_DEF; do
    COMPONENT_NAME=$(echo $COMPONENT_DEF | jq -r '.name')
    IMPORT_NAME=$(echo $COMPONENT_DEF | jq -r '.import')
    HOURS_PER_USE=$(echo $COMPONENT_DEF | jq -r '.hoursSaved')

    # Count actual uses of the component from the design system
    # This looks for patterns like:
    # import { Button } from '@envato/design-system'
    # import { Button as DSButton } from '@envato/design-system'
    # import { Box, Button, Text } from '@envato/design-system'
    USAGE_COUNT=$(find "$REPO_TEMP_DIR/$SEARCH_PATH" -type f -name "*.tsx" -o -name "*.ts" -o -name "*.jsx" -o -name "*.js" 2>/dev/null | while read file; do
      # First check if the file imports from design system
      if grep -q "from ['\"]$PACKAGE_NAME" "$file"; then
        # Then count actual component uses in the file
        grep -o "\b${IMPORT_NAME}\b" "$file" | wc -l
      fi
    done | awk '{sum += $1} END {print sum}')

    USAGE_HOURS=$(($USAGE_COUNT * $HOURS_PER_USE))
    
    if [ $USAGE_COUNT -gt 0 ]; then
      echo "  Found $USAGE_COUNT uses of $COMPONENT_NAME"
      TOTAL_COMPONENTS=$((TOTAL_COMPONENTS + 1))
    fi

    echo "{\"name\": \"$COMPONENT_NAME\", \"count\": $USAGE_COUNT, \"hoursSaved\": $USAGE_HOURS}" >> $COMPONENTS_FILE
  done

  # Build final JSON array from the line-delimited file
  COMPONENTS_BREAKDOWN=$(jq -s '.' $COMPONENTS_FILE)
  TOTAL_HOURS=$(echo "$COMPONENTS_BREAKDOWN" | jq '[.[] | .hoursSaved] | add // 0')

  # Is the repo using the latest version?
  IS_LATEST=false
  if [[ "$VERSION" == "$LATEST_VERSION"* ]]; then
    IS_LATEST=true
  fi

  # Add to this week's data
  jq ". += [{
    repo: \"$REPO_NAME\",
    version: \"$VERSION\",
    isLatest: $IS_LATEST,
    componentsUsed: $TOTAL_COMPONENTS,
    hoursSaved: $TOTAL_HOURS,
    components: $COMPONENTS_BREAKDOWN
  }]" $TMP_OUTPUT > tmp.json && mv tmp.json $TMP_OUTPUT

  # Clean up this repo's files
  rm -rf "$REPO_TEMP_DIR"
  rm -f $COMPONENTS_FILE

done

# === APPEND WEEK TO CUMULATIVE LOG ===
# Create log file if not exists
if [ ! -f "$LOG_FILE" ]; then
  echo "[]" > $LOG_FILE
fi

# Sum total hours saved for this week
TOTAL_HOURS=$(jq '[.[] | .hoursSaved] | add' $TMP_OUTPUT)

# Create log entry for this week
jq ". += [{
  week: \"$WEEK\",
  totalHoursSaved: $TOTAL_HOURS,
  systems: $(cat $TMP_OUTPUT)
}]" $LOG_FILE > tmp-log.json && mv tmp-log.json $LOG_FILE

# Final cleanup
rm -rf temp/

echo "✅ Done! Weekly impact with component breakdown saved to $LOG_FILE"
