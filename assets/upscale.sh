#!/bin/sh
for file in 1x/*.png; do
    filename=$(basename "$file")
    output_file="2x/${filename}"
    magick "$file" -filter point -resize 200% "$output_file"
done
