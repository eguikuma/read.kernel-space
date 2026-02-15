##
## Dockerfile
##
## CI 用の Docker イメージです
##

FROM node:24.13.0-slim

##
## prettier と textlint のインストール
##
## prettier
## ─── Markdown、JSON などのフォーマッターです
## textlint
## ─── Markdown のリンターです
## textlint-plugin-markdown
## ─── textlint で Markdown を解析するためのプラグインです
##
RUN npm install -g prettier textlint textlint-plugin-markdown

WORKDIR /app
