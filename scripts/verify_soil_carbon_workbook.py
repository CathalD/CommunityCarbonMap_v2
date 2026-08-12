# Check the recalculated workbook against an independent hand calculation done
# straight from data/community_soil_cores.csv -- the workshop's rule is that if
# the code and the hand calculation disagree, the hand calculation wins.
#
# Run AFTER recalc.py, otherwise every formula cell reads back as None.

import csv
import os
import sys

from openpyxl import load_workbook

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(HERE, "data", "community_soil_cores.csv")
WB = os.path.join(HERE, "data", "soil_carbon_calculation.xlsx")
TARGETS = [(0, 15), (15, 30), (30, 50), (50, 100)]
TOL = 1e-9

fails = []


def check(label, got, want, tol=TOL):
    if got is None or abs(got - want) > tol:
        fails.append(f"{label}: workbook {got!r} != hand {want!r}")


def main():
    rows = [r for r in csv.DictReader(open(SRC, encoding="utf-8-sig")) if r.get("Core Id")]
    cores = {}
    for r in rows:
        cores.setdefault(r["Core Id"], []).append(r)

    wb = load_workbook(WB, data_only=True)
    sd, cs, lx, px = (wb["3. Sample Data"], wb["4. Core Summary"],
                      wb["5. R export (layers)"], wb["6. R export (plots)"])

    # ---- sheet 3, row by row -------------------------------------------------
    depth = {}
    for i, r in enumerate(rows):
        row = 6 + i
        core = r["Core Id"]
        th = float(r["Depth"])
        a = depth.get(core, 0.0)
        b = a + th
        depth[core] = b
        q = float(r["Bulk Density"]) * float(r["SOC"]) / 100

        check(f"S3!H{row} depth_from", sd[f"H{row}"].value, a)
        check(f"S3!I{row} depth_to", sd[f"I{row}"].value, b)
        check(f"S3!Q{row} C density", sd[f"Q{row}"].value, q)
        check(f"S3!R{row} g C/cm2", sd[f"R{row}"].value, q * th)
        check(f"S3!S{row} kg C/m2", sd[f"S{row}"].value, q * th * 10)
        check(f"S3!T{row} Mg C/ha", sd[f"T{row}"].value, q * th * 100)
        check(f"S3!Z{row} cross-check",
              sd[f"Z{row}"].value,
              q - float(r["Organic Carbon Density (g/cm^2)"]))
        check(f"S3!E{row} longitude sign",
              sd[f"E{row}"].value, -abs(float(r["Longitude"])))
        for k, (t0, t1) in enumerate(TARGETS):
            col = "UVWX"[k]
            want = max(0.0, min(b, t1) - max(a, t0)) * q * 10
            check(f"S3!{col}{row} -> {t0}-{t1} cm", sd[f"{col}{row}"].value, want)

        # sheet 5 mirrors sheet 3 with the column names run_02 expects
        e = 2 + i
        assert lx[f"A{e}"].value == core, f"S5!A{e} plot_id"
        check(f"S5!B{e} depth_from", lx[f"B{e}"].value, a)
        check(f"S5!C{e} depth_to", lx[f"C{e}"].value, b)
        check(f"S5!D{e} soc g/kg", lx[f"D{e}"].value, float(r["SOC"]) * 10)
        check(f"S5!E{e} bulk_density", lx[f"E{e}"].value, float(r["Bulk Density"]))

    # ---- sheet 4, core by core ----------------------------------------------
    for j, (core, rs) in enumerate(cores.items()):
        row = 5 + j
        d = 0.0
        whole = 0.0
        t = [0.0, 0.0, 0.0, 0.0]
        for r in rs:
            th = float(r["Depth"])
            q = float(r["Bulk Density"]) * float(r["SOC"]) / 100
            a, b = d, d + th
            d = b
            whole += q * th * 10
            for k, (t0, t1) in enumerate(TARGETS):
                t[k] += max(0.0, min(b, t1) - max(a, t0)) * q * 10

        assert cs[f"A{row}"].value == core, f"S4!A{row} core id"
        check(f"S4!F{row} in-situ depth", cs[f"F{row}"].value, d)
        check(f"S4!G{row} whole-core kg C/m2", cs[f"G{row}"].value, whole)
        check(f"S4!H{row} whole-core Mg C/ha", cs[f"H{row}"].value, whole * 10)
        for k, (t0, _t1) in enumerate(TARGETS):
            col = "IJKL"[k]
            got = cs[f"{col}{row}"].value
            if d <= t0:
                if got != "no core material":
                    fails.append(f"S4!{col}{row}: expected 'no core material', got {got!r}")
            else:
                check(f"S4!{col}{row} target stock", got, t[k])
        check(f"S4!M{row} 0-30 kg C/m2", cs[f"M{row}"].value, t[0] + t[1])
        check(f"S4!N{row} 0-30 Mg C/ha", cs[f"N{row}"].value, (t[0] + t[1]) * 10)

        flag = cs[f"O{row}"].value or ""
        if (d >= 30) != flag.startswith("full"):
            fails.append(f"S4!O{row}: coverage flag {flag!r} disagrees with depth {d}")

        check(f"S6!D{2+j} observed", px[f"D{2+j}"].value, t[0] + t[1])

    n = len(rows)
    print(f"checked {n} slices x 11 values + {len(cores)} cores x 10 values")
    if fails:
        print(f"\nFAILED ({len(fails)}):")
        for f in fails[:40]:
            print("  " + f)
        sys.exit(1)
    print("all values match the hand calculation")


if __name__ == "__main__":
    main()
