#!/bin/bash

# Delete all files in project root/configs that start with "test" or "template"
find ../configs -maxdepth 1 -type f \( -name ".test*" -o -name ".template*" \) -print -delete