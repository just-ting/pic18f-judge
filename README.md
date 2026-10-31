# PIC18F Judge

以 MPLAB X Simulator（MDB）執行 PIC18F 程式並依 JSON 測資比對資料記憶體的簡易評測工具。支援 PIC assembly（`.asm`）及 XC8 C（`.c`）。

## 環境需求

- Ubuntu 24.04
- Docker
- MPLAB X 5.20
- XC8 3.10
- PIC18Fxxxx DFP

## Build


```bash
docker build -t pic18f-judge .
```

## Judge

目前範例以 assembly 模式測試 `Lab2/hard.asm` 的第 1 組測資：

```bash
docker run --rm \
  -v "$PWD:/workspace" \
  pic18f-judge -lc \
  'python3 /workspace/judge/judge.py \
    --mode asm \
    --src /workspace/submissions/Lab2/hard.asm \
    --folder Lab2 \
    --task hard \
    --case 1'
```

C 程式則將 `--mode asm` 改為 `--mode c`，並將 `--src` 指向 `.c` 檔。例如：

```bash
docker run --rm \
  -v "$PWD:/workspace" \
  pic18f-judge -lc \
  'python3 /workspace/judge/judge.py \
    --mode c \
    --src /workspace/submissions/Lab2/main.c \
    --folder Lab2 \
    --task basic \
    --case 1'
```

`$PWD` 會掛載到容器的 `/workspace`，因此 `--src` 和自訂測資路徑要使用容器內的絕對路徑。輸出檔會留在掛載目錄中。

## Testcase format

```json
{
  "chip": "18F4520",
  "writes": [
    { "addr": "0x120", "data": ["0xA2", "0xD9"] }
  ],
  "reads": [
    { "addr": "0x122", "len": 5 }
  ],
  "expect": ["0x7B", "0x5E", "0xD9", "0x85", "0x5E"]
}
```
