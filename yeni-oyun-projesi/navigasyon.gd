extends RefCounted
class_name Navigasyon

# ============================================================
# PLATFORMER PLANLAYICI v3
# Masaüstü "yüzeylerden" oluşur: görev çubuğu + ikonların üst kenarları.
# İkonlar tek yönlü platformdur: içinden geçilir, üstüne basılır.
# Her geçiş bir eylemdir (yürü, zıpla, tırman, düş, kule, köprü) ve bir
# maliyeti vardır. Dijkstra en ucuz eylem dizisini bulur; bloklar pahalı
# olduğu için sadece başka yol yoksa ya da yol çok uzunsa kullanılır.
# ============================================================

# Fizik sabitleri (stickman.gd ile eşleşmeli)
const ZIPLAMA_HIZI := 287.0
const YERCEKIMI := 980.0
const YURUME_HIZI := 300.0
const EN_DUSUK_HIZ_CARPANI := 0.8

const KENAR := 14.0              # Yüzey kenarına bu kadar içeride dur/kalk
const ZIPLAMA_MAX := 36.0        # Zıplayarak çıkılabilecek yükseklik (42px'in güvenli kısmı)
const TIRMANMA_MAX := 140.0      # Zıplama + tırmanma ile çıkılabilecek yükseklik
const KULE_BITIS := 125.0        # Kule bu kadar yaklaşınca tırmanmaya geç
const BLOK := 40.0
const MAX_KULE_BLOK := 25
const MAX_KOPRU_BLOK := 12
const YANINDA_ALT_PAY := 60.0    # Ayak, ikonun altından bu kadar aşağıdaysa bile gövde ikona değer ("yanında")

# Eylem maliyetleri (piksel yürüme eşdeğeri)
const M_YURU := 10.0
const M_ZIPLA := 60.0
const M_DUS := 40.0
const M_TIRMAN := 150.0
const M_KULE := 150.0
const M_BLOK := 300.0

var yuzeyler: Array = []        # [{id, isim, yol, x0, x1, y, h}]
var ekran: Vector2 = Vector2.ZERO

func grafi_kur(ikon_listesi: Array, ekran_boyutu: Vector2i) -> void:
	yuzeyler.clear()
	ekran = Vector2(ekran_boyutu)
	_yuzey_ekle("gorev_cubugu", "", 0.0, ekran.x, ekran.y - 50.0, 50.0)
	for ikon in ikon_listesi:
		if typeof(ikon["path"]) == TYPE_NIL or ikon["path"] == "":
			continue
		var x = float(ikon["x"])
		_yuzey_ekle(ikon.get("name", "bilinmeyen"), ikon["path"], x, x + float(ikon["width"]),
				float(ikon["y"]), float(ikon["height"]))
	print("Nav: ", yuzeyler.size(), " yüzey hazır")

func _yuzey_ekle(isim: String, yol: String, x0: float, x1: float, y: float, h: float) -> void:
	yuzeyler.append({"id": yuzeyler.size(), "isim": isim, "yol": yol, "x0": x0, "x1": x1, "y": y, "h": h})

func yuzey_bul(isim: String) -> Dictionary:
	for s in yuzeyler:
		if s["isim"] == isim:
			return s
	return {}

func hedefler() -> Array:
	var liste: Array = []
	for s in yuzeyler:
		if s["yol"] != "":
			liste.append(s)
	return liste

func uzerindeki_yuzey(ayak: Vector2) -> Dictionary:
	for s in yuzeyler:
		if absf(ayak.y - s["y"]) <= 8.0 and ayak.x >= s["x0"] - 12.0 and ayak.x <= s["x1"] + 12.0:
			return s
	return {}

func ilk_alttaki(x: float, y: float) -> Dictionary:
	"""x hizasında, y'nin altındaki ilk yüzey (düşünce nereye konacağımız)."""
	var en_iyi: Dictionary = {}
	for s in yuzeyler:
		if x >= s["x0"] and x <= s["x1"] and s["y"] > y + 2.0:
			if en_iyi.is_empty() or s["y"] < en_iyi["y"]:
				en_iyi = s
	return en_iyi

func ziplama_menzili(yukseklik: float) -> float:
	"""Kenardan kenara atlanabilecek boşluk. yukseklik > 0 = hedef yukarıda."""
	var disk = ZIPLAMA_HIZI * ZIPLAMA_HIZI - 2.0 * YERCEKIMI * yukseklik
	if disk < 0.0:
		return -1.0
	var t = (ZIPLAMA_HIZI + sqrt(disk)) / YERCEKIMI
	return YURUME_HIZI * EN_DUSUK_HIZ_CARPANI * t - 2.0 * KENAR - 20.0

# ============================================================
# PLANLAMA
# ============================================================

func plan_yap(ayak: Vector2, hedef_isim: String, gurultu: bool = true) -> Array:
	var hedef = yuzey_bul(hedef_isim)
	if hedef.is_empty():
		return []
	
	var baslangic = uzerindeki_yuzey(ayak)
	var dugumler: Array = yuzeyler.duplicate()
	if baslangic.is_empty():
		# Blok üstünde ya da bilinmeyen bir yerde duruyoruz: geçici yüzey
		baslangic = {"id": yuzeyler.size(), "isim": "_gecici", "yol": "",
				"x0": ayak.x - 16.0, "x1": ayak.x + 16.0, "y": ayak.y, "h": 0.0}
		dugumler.append(baslangic)
	
	var n = dugumler.size()
	var maliyet: Array = []
	var varis_x: Array = []
	var onceki: Array = []    # [onceki_id, adımlar]
	var kapali: Array = []
	maliyet.resize(n)
	varis_x.resize(n)
	onceki.resize(n)
	kapali.resize(n)
	for i in n:
		maliyet[i] = INF
		kapali[i] = false
	maliyet[baslangic["id"]] = 0.0
	varis_x[baslangic["id"]] = ayak.x
	
	var en_iyi_toplam = INF
	var en_iyi_son = -1
	var en_iyi_bitis: Array = []
	
	while true:
		var u = -1
		for i in n:
			if not kapali[i] and maliyet[i] < INF and (u == -1 or maliyet[i] < maliyet[u]):
				u = i
		if u == -1 or maliyet[u] >= en_iyi_toplam:
			break
		kapali[u] = true
		var a = dugumler[u]
		var ax: float = varis_x[u]
		
		var bitis = _bitis(a, ax, hedef, gurultu)
		if not bitis.is_empty() and maliyet[u] + bitis["maliyet"] < en_iyi_toplam:
			en_iyi_toplam = maliyet[u] + bitis["maliyet"]
			en_iyi_son = u
			en_iyi_bitis = bitis["adimlar"]
		
		for v in n:
			if v == u or kapali[v]:
				continue
			var k = _kenar(a, dugumler[v], ax, gurultu)
			if k.is_empty():
				continue
			if maliyet[u] + k["maliyet"] < maliyet[v]:
				maliyet[v] = maliyet[u] + k["maliyet"]
				varis_x[v] = k["varis_x"]
				onceki[v] = [u, k["adimlar"]]
	
	if en_iyi_son == -1:
		print("Nav: '", hedef_isim, "' için plan bulunamadı")
		return []
	
	var plan: Array = en_iyi_bitis.duplicate()
	var c = en_iyi_son
	while c != baslangic["id"]:
		var o = onceki[c]
		var parca: Array = o[1].duplicate()
		parca.append_array(plan)
		plan = parca
		c = o[0]
	
	var ozet: Array = []
	for adim in plan:
		ozet.append(adim["tip"])
	print("Nav: ", hedef_isim, " -> ", ozet, " (maliyet ", snapped(en_iyi_toplam, 1), ")")
	return plan

func _gurultu(m: float, acik: bool) -> float:
	return m * randf_range(0.9, 1.4) if acik else m

func _aday(en_iyi: Dictionary, m: float, varis: float, adimlar: Array) -> void:
	if en_iyi.is_empty() or m < en_iyi["maliyet"]:
		en_iyi["maliyet"] = m
		en_iyi["varis_x"] = varis
		en_iyi["adimlar"] = adimlar

func _adim(tip: String, a: Dictionary, b: Dictionary, kalkis: float, varis: float) -> Dictionary:
	return {"tip": tip, "a": a, "b": b, "kalkis_x": kalkis, "varis_x": varis}

func _kenar(a: Dictionary, b: Dictionary, ax: float, gurultu: bool) -> Dictionary:
	"""a'dan b'ye en ucuz tek geçiş. {maliyet, varis_x, adimlar} ya da {}."""
	var yukseklik: float = a["y"] - b["y"]   # pozitif = b yukarıda
	var bosluk: float = maxf(b["x0"] - a["x1"], a["x0"] - b["x1"])
	var yon: int = 1 if b["x0"] + b["x1"] > a["x0"] + a["x1"] else -1
	var ort0: float = maxf(a["x0"], b["x0"]) + KENAR
	var ort1: float = minf(a["x1"], b["x1"]) - KENAR
	var ortusuyor: bool = ort1 >= ort0
	var a_kenar: float = a["x1"] - KENAR if yon > 0 else a["x0"] + KENAR
	var b_kenar: float = b["x0"] + KENAR if yon > 0 else b["x1"] - KENAR
	var b_yakin: float = b["x0"] if yon > 0 else b["x1"]
	var en_iyi: Dictionary = {}
	
	# YÜRÜ: aynı seviyede bitişik
	if absf(yukseklik) <= 6.0 and bosluk <= 4.0:
		var varis = clampf(ax, b["x0"] + KENAR, b["x1"] - KENAR)
		_aday(en_iyi, absf(varis - ax) + M_YURU, varis, [_adim("YURU", a, b, varis, varis)])
		return en_iyi
	
	# ZIPLA: kısa yükseklik, menzil içinde
	if yukseklik <= ZIPLAMA_MAX:
		if ortusuyor and yukseklik > 6.0:
			var k = clampf(ax, ort0, ort1)
			_aday(en_iyi, absf(k - ax) + _gurultu(M_ZIPLA, gurultu), k, [_adim("ZIPLA", a, b, k, k)])
		elif not ortusuyor and bosluk <= ziplama_menzili(yukseklik):
			_aday(en_iyi, absf(a_kenar - ax) + absf(b_kenar - a_kenar) + _gurultu(M_ZIPLA, gurultu), b_kenar,
					[_adim("ZIPLA", a, b, a_kenar, b_kenar)])
	
	# TIRMAN: ikonun önünde dur, yukarı tırman
	if yukseklik > 6.0 and yukseklik <= TIRMANMA_MAX and ortusuyor:
		var k = clampf(ax, ort0, ort1)
		_aday(en_iyi, absf(k - ax) + _gurultu(M_TIRMAN + yukseklik * 0.3, gurultu), k, [_adim("TIRMAN", a, b, k, k)])
	
	# DÜŞ (içinden): üstünde durduğumuz ikonun içinden aşağı süzül
	if yukseklik < -6.0 and ortusuyor and a["id"] != 0:
		var k = clampf(ax, ort0, ort1)
		if ilk_alttaki(k, a["y"]).get("id", -1) == b["id"]:
			_aday(en_iyi, absf(k - ax) + _gurultu(M_DUS, gurultu), k, [_adim("DUS_IC", a, b, k, k)])
	
	# DÜŞ (kenardan): kenardan yürüyüp aşağı düş
	if yukseklik < -6.0:
		for taraf in [-1, 1]:
			var kenar_x: float = a["x1"] if taraf > 0 else a["x0"]
			var konus_x: float = kenar_x + taraf * 30.0
			if konus_x < 0.0 or konus_x > ekran.x:
				continue
			if ilk_alttaki(konus_x, a["y"]).get("id", -1) == b["id"]:
				var k = kenar_x - taraf * KENAR
				_aday(en_iyi, absf(k - ax) + _gurultu(M_DUS + 10.0, gurultu), konus_x,
						[_adim("DUS_KENAR", a, b, k, konus_x)])
	
	# KULE: çok yüksek, altından blok yığarak çık
	if yukseklik > TIRMANMA_MAX and ortusuyor:
		var blok_sayisi = int(ceil((yukseklik - KULE_BITIS) / BLOK))
		if blok_sayisi <= MAX_KULE_BLOK:
			var k = clampf(ax, ort0, ort1)
			var kule = _adim("KULE", a, b, k, k)
			kule["hedef_ayak_y"] = b["y"] + KULE_BITIS
			_aday(en_iyi, absf(k - ax) + _gurultu(M_KULE + blok_sayisi * M_BLOK + M_TIRMAN, gurultu), k,
					[kule, _adim("TIRMAN", a, b, k, k)])
	
	# KÖPRÜ: zıplanamayacak boşluk, yana blok döşeyerek geç
	if not ortusuyor and bosluk > 0.0 and yukseklik <= TIRMANMA_MAX:
		var menzil = ziplama_menzili(yukseklik) if yukseklik <= ZIPLAMA_MAX else -1.0
		if menzil < 0.0 or bosluk > menzil:
			var takip: String = "ZIPLA" if menzil >= 0.0 else "TIRMAN"
			var gereken: float = bosluk - menzil if takip == "ZIPLA" else bosluk + 34.0
			var blok_sayisi = int(ceil(gereken / BLOK))
			if blok_sayisi <= MAX_KOPRU_BLOK:
				var kopru = _adim("KOPRU", a, b, a_kenar, b_kenar)
				kopru["yon"] = yon
				kopru["uc_x"] = a["x1"] if yon > 0 else a["x0"]
				kopru["takip"] = takip
				kopru["menzil"] = menzil
				kopru["b_yakin"] = b_yakin
				var takip_m = M_ZIPLA if takip == "ZIPLA" else M_TIRMAN
				_aday(en_iyi, absf(a_kenar - ax) + bosluk + _gurultu(blok_sayisi * M_BLOK + takip_m, gurultu),
						b_kenar, [kopru])
	
	return en_iyi

func _bitis(a: Dictionary, ax: float, hedef: Dictionary, gurultu: bool) -> Dictionary:
	"""a yüzeyinden hedefe 'üstünde ya da yanında' olacak şekilde son adım."""
	var hx0: float = hedef["x0"]
	var hx1: float = hedef["x1"]
	var orta: float = (hx0 + hx1) * 0.5
	
	if a["id"] == hedef["id"]:
		var x = clampf(orta + randf_range(-15.0, 15.0), a["x0"] + KENAR, a["x1"] - KENAR)
		return {"maliyet": absf(x - ax), "adimlar": [_adim("YURU", a, a, x, x)]}
	
	var bant_ust: float = hedef["y"] + 8.0
	var bant_alt: float = hedef["y"] + hedef["h"] + YANINDA_ALT_PAY
	var b0: float = maxf(a["x0"] + KENAR, hx0 - 10.0)
	var b1: float = minf(a["x1"] - KENAR, hx1 + 10.0)
	
	# Ayaklarımız ikonun hizasındaysa: yanına yürü
	if a["y"] >= bant_ust and a["y"] <= bant_alt:
		if b1 >= b0:
			var x = clampf(ax, b0, b1)
			return {"maliyet": absf(x - ax), "adimlar": [_adim("YURU", a, a, x, x)]}
		# Arada boşluk var: hedefin hizasına kadar köprü
		var yon: int = 1 if orta > ax else -1
		var uc_x: float = a["x1"] if yon > 0 else a["x0"]
		var bosluk: float = (hx0 - 10.0 - uc_x) if yon > 0 else (uc_x - hx1 - 10.0)
		var blok_sayisi = int(ceil((bosluk + 20.0) / BLOK))
		if blok_sayisi >= 1 and blok_sayisi <= MAX_KOPRU_BLOK:
			var k = a["x1"] - KENAR if yon > 0 else a["x0"] + KENAR
			var kopru = _adim("KOPRU", a, hedef, k, orta)
			kopru["yon"] = yon
			kopru["uc_x"] = uc_x
			kopru["takip"] = "HEDEF"
			kopru["b_yakin"] = hx0 - 10.0 if yon > 0 else hx1 + 10.0
			return {"maliyet": absf(k - ax) + bosluk + _gurultu(blok_sayisi * M_BLOK, gurultu), "adimlar": [kopru]}
		return {}
	
	# Çok aşağıdayız ve hedefin altındayız: hizasına kadar kule
	if a["y"] > bant_alt:
		var k0: float = maxf(a["x0"], hx0) + KENAR
		var k1: float = minf(a["x1"], hx1) - KENAR
		if k1 >= k0:
			var hedef_ayak: float = hedef["y"] + hedef["h"] + 30.0
			var blok_sayisi = int(ceil((a["y"] - hedef_ayak) / BLOK))
			if blok_sayisi <= MAX_KULE_BLOK:
				var k = clampf(ax, k0, k1)
				var kule = _adim("KULE", a, hedef, k, k)
				kule["hedef_ayak_y"] = hedef_ayak
				return {"maliyet": absf(k - ax) + _gurultu(M_KULE + blok_sayisi * M_BLOK, gurultu), "adimlar": [kule]}
	return {}
