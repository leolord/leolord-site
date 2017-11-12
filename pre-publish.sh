#!/bin/bash

rm -rf ./_site
rm -rf category
rm -rf tag
rm -rf date

jekyll b

mv ./_site/category .
mv ./_site/tag .
mv ./_site/date .
