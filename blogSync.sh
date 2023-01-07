#!/bin/bash

SOURCE_PATH="/e/个人/blog/博客园/"
BLOG_PATH="/e/个人/blog/cnblogs"

rsync --exclude-from=$SOURCE_PATH/.gitignore -avz $SOURCE_PATH $BLOG_PATH