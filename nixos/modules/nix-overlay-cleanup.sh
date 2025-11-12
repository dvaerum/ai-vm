#!/usr/bin/env bash
# Complete Nix Overlay Cleanup Script
# Analyzes dead paths and deletes them using nix-store --delete

# No set -e - deletion failures are expected

show_usage() {
    echo "Usage: $0 [--analyze|--delete|--full]"
    echo ""
    echo "Options:"
    echo "  --analyze   : Find dead paths in overlay (takes ~2 min)"
    echo "  --delete    : Delete previously analyzed paths"
    echo "  --full      : Run analysis then deletion (one-shot)"
    echo ""
    echo "Example:"
    echo "  $0 --full   # Analyze and clean in one go"
}

analyze_paths() {
    echo "=== Analyzing Nix Store Overlay ==="
    echo ""

    overlay_dir="/nix/.rw-store/upper"

    if [ ! -d "$overlay_dir" ]; then
        echo "ERROR: Overlay directory not found: $overlay_dir"
        exit 1
    fi

    total=$(ls "$overlay_dir" | wc -l)
    echo "Found $total entries in overlay"
    echo ""

    echo "Step 1: Finding all dead paths in store..."
    dead_list="/tmp/nix-dead-paths.txt"
    nix-store --gc --print-dead > "$dead_list" 2>&1

    dead_count=$(grep "^/nix/store/" "$dead_list" | wc -l)
    echo "✓ Found $dead_count dead paths in total store"
    echo ""

    echo "Step 2: Finding which dead paths are in overlay..."
    overlay_list="/tmp/nix-overlay-paths.txt"
    overlay_dead="/tmp/nix-overlay-deletable.txt"

    ls "$overlay_dir" | while read name; do
        echo "/nix/store/$name"
    done > "$overlay_list"

    overlay_total=$(wc -l < "$overlay_list")
    echo "✓ Found $overlay_total paths in overlay"
    echo ""

    echo "Step 3: Finding intersection (overlay paths that are dead)..."
    comm -12 <(sort "$overlay_list") <(sort "$dead_list" | grep "^/nix/store/") > "$overlay_dead"

    deletable=$(wc -l < "$overlay_dead")
    in_use=$((overlay_total - deletable))

    echo ""
    echo "=== Analysis Complete ==="
    echo "Total overlay paths:  $overlay_total"
    echo "In use (keep):        $in_use"
    echo "Deletable (dead):     $deletable"
    echo ""

    if [ $deletable -gt 0 ]; then
        echo "Sample of deletable paths:"
        head -20 "$overlay_dead"
        if [ $deletable -gt 20 ]; then
            echo "... and $((deletable - 20)) more"
        fi
        echo ""
        echo "Full list saved to: $overlay_dead"
        return 0
    else
        echo "No deletable paths found. Everything is in use!"
        return 1
    fi
}

delete_paths() {
    echo "=== Deleting Dead Paths ==="
    echo ""

    overlay_dead="/tmp/nix-overlay-deletable.txt"

    if [ ! -f "$overlay_dead" ]; then
        echo "ERROR: No deletable paths list found."
        echo "Run '$0 --analyze' first."
        exit 1
    fi

    total=$(wc -l < "$overlay_dead")

    if [ $total -eq 0 ]; then
        echo "No paths to delete."
        exit 0
    fi

    echo "Processing $total dead paths..."
    echo "Paths still referenced will be skipped automatically"
    echo ""

    deleted=0
    skipped=0
    count=0

    start_time=$(date +%s)

    while IFS= read -r path; do
        ((count++))

        # Try to delete - capture output and handle errors
        output=$(nix-store --delete "$path" 2>&1) || true

        if echo "$output" | grep -q "deleting "; then
            ((deleted++))
            echo "[$count/$total] ✓ Deleted: $(basename $path)"
        elif echo "$output" | grep -q "still alive"; then
            ((skipped++))
            # Only show every 10th skip to reduce noise
            if [ $((skipped % 10)) -eq 0 ]; then
                echo "[$count/$total] ⊘ Skipped $skipped (still referenced)"
            fi
        else
            # Some other output/error
            ((skipped++))
        fi

        # Progress summary every 100 paths
        if [ $((count % 100)) -eq 0 ]; then
            elapsed=$(($(date +%s) - start_time))
            avg_time=$(echo "scale=2; $elapsed / $count" | bc 2>/dev/null || echo "0")
            remaining=$(echo "scale=0; ($total - $count) * $avg_time" | bc 2>/dev/null || echo "0")
            echo ""
            echo "=== Progress: $count/$total (~${remaining}s remaining) ==="
            echo "    Deleted: $deleted | Skipped: $skipped | Speed: ${avg_time}s/path"
            echo ""
        fi

    done < "$overlay_dead"

    end_time=$(date +%s)
    elapsed=$((end_time - start_time))

    echo ""
    echo "=== COMPLETE (${elapsed}s total) ==="
    echo "Total processed: $total"
    echo "Deleted:         $deleted paths"
    echo "Skipped:         $skipped paths (still referenced)"
    echo ""

    if [ $deleted -gt 0 ]; then
        echo "Final disk usage:"
        df -h / | grep -E "Filesystem|/dev/vda"
        echo ""
        echo "Overlay size:"
        du -sh /nix/.rw-store/upper 2>/dev/null
    else
        echo "No paths were deleted - all are still referenced."
        echo "Run 'nix-store --gc' to perform full garbage collection."
    fi
}

# Main script
case "$1" in
    --analyze)
        analyze_paths
        echo ""
        echo "To delete these paths, run: $0 --delete"
        ;;
    --delete)
        delete_paths
        ;;
    --full)
        echo "=== Full Cleanup (Analyze + Delete) ==="
        echo ""
        if analyze_paths; then
            echo ""
            echo "Starting deletion..."
            echo ""
            delete_paths
        fi
        ;;
    *)
        show_usage
        exit 1
        ;;
esac