# Dataset directory

学習画像はGit管理しません。`scripts/prepare_dataset.py` が以下を生成します。

```text
dataset/
├── train/       # PNG + 同名の.txtキャプション
├── validation/  # 評価用。学習configからは参照しない
├── excluded/    # v1で除外した画像
└── dataset-audit.json
```

元画像は変更しません。生成後も `.gitignore` によりGitHubへ追加されません。
