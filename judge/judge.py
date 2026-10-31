import argparse, subprocess, tempfile, re, os, sys, json, shutil
from pathlib import Path
"""
docker run --rm -it -v "$PWD:/workspace" pic18f-judge
python3 judge.py --mode asm --src /workspace/submissions/Lab2/hard.asm --folder Lab2 --task hard --case 1 --wait_ms 500
"""
# Environment variables
MPASMX = shutil.which("mpasmx") or "/opt/microchip/mplabx/mpasmx/mpasmx"
XC8_CC = shutil.which("xc8-cc") or "/opt/microchip/xc8/pic/bin/driver18"
MDB    = shutil.which("mdb.sh") or "/opt/microchip/mplabx/mplab_platform/bin/mdb.sh"

# RUN
def run(cmd, **kw):
    p = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, **kw)
    return p.returncode, p.stdout

def ensure_int(v):
    if isinstance(v, int): return v
    if isinstance(v, str): return int(v, 0)
    raise ValueError("Not int or str")

def to_hex_list(arr):
    return [f"0x{x:02X}" for x in arr]

"""
"writes": [
  { "addr": "0x20", "data": [0xA2, 0x12, 0x34] },
  { "addr": "0x30", "data": [0x08] }
]

transformed to

writes = [
    (0x20, [0xA2, 0x12, 0x34]),
    (0x30, [0x08])
]
"""
def load_case_json(default_path, override=None):
    path = override or default_path
    with open(path, "r") as f:
        cfg = json.load(f)
    
    writes = []
    for w in cfg.get("writes", []):
        a = ensure_int(w["addr"])
        data = [ensure_int(x) & 0xFF for x in w["data"]]
        writes.append((a, data))
    reads_raw = cfg.get("reads", [])
    if not reads_raw and "read" in cfg:
        # single read
        r = cfg["read"]
        reads_raw = [r]
    reads = [(ensure_int(r["addr"]), int(r["len"])) for r in reads_raw]
    expect = cfg.get("expect")
    if expect and isinstance(expect[0], list):
        exp_flat = [ensure_int(x)&0xFF for block in expect for x in block]
    else:
        exp_flat = [ensure_int(x)&0xFF for x in expect]
    chip = cfg.get("chip")
    return {"chip": chip, "writes": writes, "reads": reads, "expect": exp_flat, "raw": cfg}

# Build .asm or .c
def build(mode, src, chip, folder_name, task):
    folder_root  = Path("/workspace/submissions") / folder_name
    build_dir = folder_root / "build"
    dist_dir  = folder_root / "dist"
    build_dir.mkdir(parents=True, exist_ok=True)
    dist_dir.mkdir(parents=True, exist_ok=True)

    src = Path(src).resolve()

    if mode == "asm":
        mpasmx_bin = MPASMX
        mplink_bin = "/opt/microchip/mplabx/mpasmx/mplink"
        lkr_dir    = "/opt/microchip/mplabx/mpasmx/LKR"
        lkr_file   = f"{lkr_dir}/{chip.lower()}_g.lkr" 

        obj_dir = build_dir / f"{task}.o"
        lst_dir = build_dir / f"{task}.lst"
        err_dir = build_dir / f"{task}.err"
        cof_dir = dist_dir  / f"{folder_name}.X.debug.cof"
        map_dir = dist_dir  / f"{folder_name}.X.debug.map"

        # assemble
        # mpasmx -p<> -l<path> -procsre<path> -c -o<path> <src>
        rc1, out1 = run([mpasmx_bin, f"-p{chip}", f"-l{lst_dir}", f"-e{err_dir}", "-c", f"-o{obj_dir}", str(src)])
        if rc1 != 0 or not obj_dir.exists():
            return rc1, out1, None

        # link
        # mplink <lkr> -p<procsr> -o <cof> -m <map> -x <obj>
        rc2, out2 = run([mplink_bin, lkr_file, f"-p{chip}", "-o", str(cof_dir), "-m", str(map_dir), "-x", str(obj_dir)])
        log = (out1 or "") + "\n" + (out2 or "") # assemble + link message
        if rc2 != 0 or not cof_dir.exists():
            cof_dir = None

        return rc2, log, str(cof_dir) if cof_dir else None

    else:
        # xc8-cc -p<chip> --outdir=<dir> <src>
        # to .elf
        rc, out = run([XC8_CC, f"--chip={chip}", f"--outdir={build_dir}", str(src)])
        elf = None
        found = list(build_dir.glob("*.elf"))
        elf = str(found[0]) if found else None

        return rc, out, elf

# mdb script
def make_write_lines(writes):
    #（w addr value）
    lines = []
    for base, byte in writes:
        for i, value in enumerate(byte):
            lines.append(f"w 0x{base+i:04X} 0x{value:02X}")
    return "\n".join(lines)

def gen_mdb_script(chip, prog_path, writes, reads, break_label=None, wait_ms=0):
    lines = [
        f"device PIC{chip}",
        "hwtool SIM",
        f"program {prog_path}",
        "reset",
        make_write_lines(writes),
        "run",
        f"wait {wait_ms}",
        "halt"
    ]
    # read ln bytes from addr
    for addr, ln in reads:
        lines.append(f"x /r{ln}xb 0x{addr:04X}")
    lines.append("quit")

    script = "\n".join(lines) + "\n"
    
    script_path = Path(__file__).parent / "mdb_script.txt"
    with open(script_path, "w", encoding="utf-8") as f:
        f.write(script)

    return str(script_path)

def parse_x_output(text, reads):
    lines = text.splitlines()
    # x /rNxb 0xADDR
    pat_cmd = re.compile(r'^x\s+/r(\d+)xb\s+0x([0-9A-Fa-f]+)')
    # 0x__: two hex digits
    pat_hex2 = re.compile(r'\b([0-9A-Fa-f]{2})\b')
    got_all = []

    x_idx_list = []
    for i, line in enumerate(lines):
        if pat_cmd.search(line.strip()):
            x_idx_list.append(i)

    for xi in x_idx_list:
        m = pat_cmd.search(lines[xi].strip())
        need = int(m.group(1)) if m else 0
        vals = []
        for j in range(xi+1, len(lines)):
            s = lines[j].strip()
            if not s or s.lower().startswith("quit"): break
            vals.extend(int(h,16) for h in pat_hex2.findall(s))
            if len(vals) >= need: break
        got_all.extend(vals[:need])

    return got_all

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--mode", choices=["asm","c"], required=True)
    ap.add_argument("--src", required=True)
    ap.add_argument("--folder", required=True, help="task folder name, e.g., Lab1")
    ap.add_argument("--task", required=True, help="task name, e.g., basic/advance/hard")
    ap.add_argument("--case", type=int, required=True, help="testcase number, e.g., 1/2/3")
    ap.add_argument("--chip", default="18F4520")
    ap.add_argument("--testcase", default=None, help="optional: specify JSON test data path")
    ap.add_argument("--wait_ms", type=int, default=500)
    args = ap.parse_args()
    # default JSON path: /workspace/submissions/{folder}/testcase/{task}_{case}.json
    default_json = Path("/workspace/submissions")/args.folder/"testcase"/f"{args.task}_{args.case}.json"
    case_cfg = load_case_json(str(default_json), args.testcase)
    if case_cfg["chip"]:
        args.chip = case_cfg["chip"]

    # build
    rc, build_log, prog_path = build(args.mode, args.src, args.chip, args.folder, args.task)
    if rc != 0 or not prog_path or not os.path.exists(prog_path):
        print("COMPILE_ERROR")
        print(build_log)
        sys.exit(1)

    # generate mdb script
    reads = case_cfg["reads"]
    mdb_path = gen_mdb_script(
        chip=args.chip,
        prog_path=prog_path,
        writes=case_cfg["writes"],
        reads=reads,
        wait_ms=args.wait_ms
    )

    # run mdb.sh
    rc, mdb_log = run([MDB, mdb_path])

    got = parse_x_output(mdb_log, reads)
    expect = case_cfg["expect"]

    ok = (got == expect) if expect else True 
    if ok:
        print("expect:", to_hex_list(expect))
        print("got   :", to_hex_list(got))
        print("AC" if ok else "WA")
    if not ok:
        print("expect:", to_hex_list(expect))
        print("got   :", to_hex_list(got))
        print("\n--- mdb log ---\n" + mdb_log)

if __name__ == "__main__":
    main()