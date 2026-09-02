"""
Masaustu ikon konumlarini cikaran prototip script.
Bu scripti WINDOWS bilgisayarinda calistirman gerekiyor (Linux'ta calismaz).

Kurulum:
    pip install pywinauto pywin32

Calistirma:
    python harita_cikar.py

Cikti:
    harita.json dosyasi olusturur ve konsola ozet basar.
"""

import ctypes
import json
import os
import sys

# --- 1) DPI awareness: yanlis koordinat almamak icin sart ---
try:
    ctypes.windll.shcore.SetProcessDpiAwareness(2)  # PER_MONITOR_AWARE
except Exception:
    try:
        ctypes.windll.user32.SetProcessDPIAware()
    except Exception:
        pass

try:
    from pywinauto import Desktop
except ImportError:
    print("pywinauto bulunamadi. Once 'pip install pywinauto pywin32' calistir.")
    sys.exit(1)


def get_screen_size():
    user32 = ctypes.windll.user32
    return user32.GetSystemMetrics(0), user32.GetSystemMetrics(1)


def find_desktop_listview():
    """
    Masaustu hiyerarsisi: Progman -> SHELLDLL_DefView -> SysListView32
    Bazi sistemlerde WorkerW altinda da olabilir, ikisini de deniyoruz.
    """
    desktop = Desktop(backend="uia")

    candidates = []
    # Progman altinda ara
    try:
        progman = desktop.window(class_name="Progman")
        candidates.append(progman.child_window(class_name="SysListView32", control_type="List"))
    except Exception:
        pass

    # WorkerW altinda ara (bazi Windows surumlerinde ikonlar burada render edilir)
    try:
        for w in desktop.windows(class_name="WorkerW"):
            try:
                lv = w.child_window(class_name="SysListView32", control_type="List")
                if lv.exists():
                    candidates.append(lv)
            except Exception:
                continue
    except Exception:
        pass

    for c in candidates:
        try:
            if c.exists():
                return c
        except Exception:
            continue

    return None


def resolve_shortcut_target(lnk_path):
    """.lnk dosyasinin gercek hedefini coz (varsa)."""
    try:
        import win32com.client
        shell = win32com.client.Dispatch("WScript.Shell")
        shortcut = shell.CreateShortCut(lnk_path)
        return shortcut.Targetpath or None
    except Exception:
        return None


def resolve_url_shortcut(url_path):
    """.url dosyasini oku, URL= veya IconFile= satirindan hedef bul.
    Steam/Epic gibi launcher'lar genelde steam://rungameid/xxxx seklinde
    bir protokol linki koyar, gercek exe yolu degil. Bu durumda IconFile
    satirindaki exe yolunu fallback olarak kullaniyoruz."""
    try:
        with open(url_path, "r", encoding="utf-8", errors="ignore") as f:
            content = f.read()
        url_line = None
        icon_line = None
        for line in content.splitlines():
            if line.startswith("URL="):
                url_line = line[4:].strip()
            elif line.startswith("IconFile="):
                icon_line = line[9:].strip()
        # Eger URL gercek bir dosya yoluysa onu kullan
        if url_line and os.path.isfile(url_line):
            return url_line
        # Degilse (steam://, http:// gibi protokolse) icon exe'sini fallback yap
        if icon_line and os.path.isfile(icon_line):
            return icon_line
        return url_line or icon_line
    except Exception:
        return None


# Windows'un ozel/sanal klasorleri - dosya sisteminde karsiligi olmayanlar
SPECIAL_FOLDERS = {
    "geri dönüşüm kutusu": "special:recycle_bin",
    "recycle bin": "special:recycle_bin",
    "denetim masası": "special:control_panel",
    "control panel": "special:control_panel",
    "bu bilgisayar": "special:this_pc",
    "this pc": "special:this_pc",
    "ağ": "special:network",
    "network": "special:network",
}


def main():
    screen_w, screen_h = get_screen_size()
    print(f"Ekran cozunurlugu: {screen_w}x{screen_h}")

    listview = find_desktop_listview()
    if listview is None:
        print("HATA: Masaustu SysListView32 kontrolu bulunamadi.")
        print("Ipucu: Masaustunde bos bir alana tiklayip scripti tekrar dene.")
        sys.exit(1)

    items = listview.children(control_type="ListItem")
    print(f"{len(items)} adet ikon bulundu.\n")

    desktop_folder = os.path.join(os.environ.get("USERPROFILE", ""), "Desktop")
    public_desktop = r"C:\Users\Public\Desktop"

    icons = []
    for item in items:
        try:
            rect = item.rectangle()
            name = item.window_text()
        except Exception as e:
            print(f"  [atlandi] bir item okunamadi: {e}")
            continue

        # Gercek dosya yolunu bulmayi dene
        full_path = None
        item_type = "unknown"

        # Once ozel klasor mu diye bak (dosya sisteminde karsiligi yok)
        special = SPECIAL_FOLDERS.get(name.strip().lower())
        if special:
            full_path = special
            item_type = "special"
        else:
            for base in (desktop_folder, public_desktop):
                candidate = os.path.join(base, name)
                if os.path.isfile(candidate):
                    full_path = candidate
                    item_type = "file"
                    break
                if os.path.isdir(candidate):
                    full_path = candidate
                    item_type = "folder"
                    break
                lnk_candidate = candidate + ".lnk"
                if os.path.isfile(lnk_candidate):
                    target = resolve_shortcut_target(lnk_candidate)
                    full_path = target or lnk_candidate
                    item_type = "shortcut"
                    break
                url_candidate = candidate + ".url"
                if os.path.isfile(url_candidate):
                    target = resolve_url_shortcut(url_candidate)
                    full_path = target or url_candidate
                    item_type = "url_shortcut"
                    break

        icon_data = {
            "name": name,
            "path": full_path,
            "type": item_type,
            "x": rect.left,
            "y": rect.top,
            "width": rect.width(),
            "height": rect.height(),
        }
        icons.append(icon_data)

        status = "OK " if full_path else "???"
        print(f"  [{status}] {name!r:40s} pos=({rect.left},{rect.top}) "
              f"size=({rect.width()}x{rect.height()}) -> {full_path}")

    harita = {
        "screen": {"width": screen_w, "height": screen_h},
        "icons": icons,
    }

    with open("harita.json", "w", encoding="utf-8") as f:
        json.dump(harita, f, ensure_ascii=False, indent=2)

    print(f"\nharita.json olusturuldu. Toplam {len(icons)} ikon kaydedildi.")
    matched = sum(1 for i in icons if i["path"])
    print(f"Yol eslesmesi basarili: {matched}/{len(icons)}")


if __name__ == "__main__":
    main()