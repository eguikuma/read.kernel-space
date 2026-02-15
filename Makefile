##
## Makefile
##
## プロジェクト共通の設定ファイルです
##

.PHONY: build ci help

CI_IMAGE = read-kernel-space-ci

##
## ヘルプ
##
help:
	@echo "─── 使い方"
	@echo "────── make build"
	@echo "───────── Docker イメージをビルドします"
	@echo "────── make ci"
	@echo "───────── フォーマット + リントを実行します"

##
## Docker イメージのビルド
##
build:
	docker build -t $(CI_IMAGE) .ci/

##
## 継続的インテグレーション (CI)
##
## prettier
## ─── Markdown、JSON などを整形します
## textlint
## ─── Markdown の文章の品質を確認します
##
ci:
	@docker run --rm --user $$(id -u):$$(id -g) -v $(PWD):/app $(CI_IMAGE) sh -c '\
		prettier --write "**/*.md" "**/*.json" --ignore-path .gitignore'
	@docker run --rm --user $$(id -u):$$(id -g) -v $(PWD):/app $(CI_IMAGE) sh -c '\
		textlint --rulesdir .ci/textlint-rules -c .ci/.textlintrc.json --ignore-path .ci/.textlintignore "**/*.md"'
