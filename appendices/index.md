---
layout: default
title: read.kernel-space
---

# [appendix：補足資料](#appendix) {#appendix}

## [このディレクトリについて](#about-this-directory) {#about-this-directory}

メインのトピック（01-kernel 〜 07-cgroup）では扱いきれない補足的な内容をまとめた資料置き場です

メインの学習順序とは独立しているため、必要なときに参照してください

---

## [補足資料の一覧](#appendix-list) {#appendix-list}

{% assign appendix_pages = site.pages | where_exp: "p", "p.url contains '/appendices/'" | where_exp: "p", "p.url != '/appendices/'" | sort: "title" %}
{% for p in appendix_pages %}

- [{{ p.title }}]({{ p.url | relative_url }})
  {% endfor %}
