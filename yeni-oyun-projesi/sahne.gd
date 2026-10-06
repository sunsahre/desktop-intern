extends Node2D

# --- NAVİGASYON SİSTEMİ ---
var nav: Navigasyon = null
var ikon_verileri: Array = []  # harita.json'dan okunan ikon listesi
var hedef_zamanlayici: Timer = null
const HEDEF_BEKLEME_SURESI_MIN = 2.0  # Hedefe varınca min bekleme
const HEDEF_BEKLEME_SURESI_MAX = 8.0  # Hedefe varınca max bekleme

const IKON_KATMANI = 3  # İkonlar ve bloklar: tek yönlü platform katmanı (stickman.gd ile aynı)

# Modlar
@export var otomatik_mod: bool = true # True=Kendi gezer, False=Fareyle komut bekler

# --- MOUSE İLE TUTMA & FIRLATMA (sol tık) ---
var tutulmus: bool = false                    # Stickman tutulmuş mu?
var fare_pozisyonu: Vector2 = Vector2.ZERO    # Güncel fare pozisyonu
const TUTMA_YARICAPI = 50.0
const FIRLATMA_SONRASI_BEKLEME = 1.0          # Kendine geldikten sonra AI'ın yeniden başlaması

# --- TIKLAMA GEÇİRME ALANI ---
# window_set_mouse_passthrough pahalı; her kare çağırmak hareketi takıltıyordu
const GECIS_GUNCELLEME_MESAFESI = 12.0
var _son_gecis_pozisyonu: Vector2 = Vector2(INF, INF)
var _son_blok_sayisi: int = -1
var _gecis_kapali: bool = false

var son_hedefler: Array = []                   # Son gidilen hedefler (tekrar engeli)
const SON_HEDEF_HAFIZA = 3                     # Kaç hedef hatırla

# --- MANUEL HEDEFLEME (sağ tık sürükle & bırak) ---
var surukleniyor: bool = false

func _ready() -> void:
	
	# --- PENCERE VE ŞEFFAFLIK AYARLARI ---
	# 1. Arka plan rengini zorla "Hiçlik" (Tamamen Saydam) yap!
	RenderingServer.set_default_clear_color(Color(0, 0, 0, 0))
	get_viewport().transparent_bg = true
	
	# 2. Pencereyi çerçevesiz, şeffaf ve her zaman en üstte tut
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_TRANSPARENT, true)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
	
	# 3. Ekranı tam masaüstü boyutuna esnet
	var gercek_ekran = DisplayServer.screen_get_size()
	DisplayServer.window_set_position(Vector2i(0, 0))
	DisplayServer.window_set_size(gercek_ekran)
	
	# 4. Tıklama geçirme: Polygon yöntemi kullanıyoruz (flag değil!)
	# Boş polygon = başlangıçta her yere tıklama geçer, _process'te güncellenir
	DisplayServer.window_set_mouse_passthrough(PackedVector2Array())
	# ------------------------------------

	# Masaüstü ikonlarını güncelle (Python scriptini çalıştır)
	print("Masaüstü ikonları taranıyor... Lütfen bekleyin.")
	var python_yolu = ProjectSettings.globalize_path("res://../.venv/Scripts/python.exe")
	var script_yolu = ProjectSettings.globalize_path("res://../test.py")
	OS.execute(python_yolu, [script_yolu])
	print("Tarama tamamlandı!")
	
	# Haritayı (JSON) yükle
	haritayükle("res://harita.json")
	
	# --- GÖREV ÇUBUĞU (ZEMİN) OLUŞTURMA ---
	var gorev_cubugu = StaticBody2D.new()
	var cubuk_alani = CollisionShape2D.new()
	var cubuk_geo = RectangleShape2D.new()
	
	var ekran_boyutu = DisplayServer.screen_get_size()
	var cubuk_yuksekligi = 50.0 
	var cubuk_genisligi = float(ekran_boyutu.x)
	
	cubuk_geo.size = Vector2(cubuk_genisligi, cubuk_yuksekligi)
	cubuk_alani.shape = cubuk_geo
	
	var cubuk_x = cubuk_genisligi / 2.0
	var cubuk_y = float(ekran_boyutu.y) - (cubuk_yuksekligi / 2.0)
	gorev_cubugu.position = Vector2(cubuk_x, cubuk_y)
	
	var cubuk_renk = ColorRect.new()
	cubuk_renk.size = Vector2(cubuk_genisligi, cubuk_yuksekligi)
	cubuk_renk.color = Color(0.2, 0.2, 0.8, 0.5) 
	cubuk_renk.position = Vector2(-cubuk_genisligi / 2.0, -cubuk_yuksekligi / 2.0)
	
	gorev_cubugu.add_child(cubuk_renk)
	gorev_cubugu.add_child(cubuk_alani)
	add_child(gorev_cubugu)
	# ------------------------------------
	
	# --- NAVİGASYON SİSTEMİNİ KUR ---
	nav = Navigasyon.new()
	var ekran = DisplayServer.screen_get_size()
	nav.grafi_kur(ikon_verileri, ekran)
	
	# Stickman sinyalini bağla
	var stickman = get_node_or_null("Stickman")
	if stickman:
		stickman.rota_tamamlandi.connect(_hedefe_varildi)
		stickman.blok_koy.connect(_blok_yerlestir)
		stickman.yere_indi.connect(_firlatmadan_kurtuldu)
		stickman.OYUNCU_KONTROLU = false  # AI kontrolüne geç
		stickman.nav = nav
		# İlk hedefi 2 saniye sonra seç (düşüp yere insene kadar bekle)
		hedef_zamanlayici = Timer.new()
		hedef_zamanlayici.one_shot = true
		hedef_zamanlayici.wait_time = 2.0
		hedef_zamanlayici.timeout.connect(_yeni_hedef_sec)
		add_child(hedef_zamanlayici)
		hedef_zamanlayici.start()
		print("AI navigasyon aktif!")

# Her frame'de stickman etrafındaki tıklanabilir alanı güncelle
func _process(_delta: float) -> void:
	var stickman_node = get_node_or_null("Stickman")
	if not stickman_node:
		return
	
	# --- TIKLANABILIR ALAN ---
	# Tutarken/sürüklerken tüm pencere fareyi yakalasın ki hızlı savurmada kaçmasın
	if tutulmus or surukleniyor:
		if not _gecis_kapali:
			DisplayServer.window_set_mouse_passthrough(PackedVector2Array())
			_gecis_kapali = true
		return
	
	var pos = stickman_node.global_position
	var bloklar = get_tree().get_nodes_in_group("bloklar")
	if not _gecis_kapali and bloklar.size() == _son_blok_sayisi \
			and pos.distance_to(_son_gecis_pozisyonu) < GECIS_GUNCELLEME_MESAFESI:
		return
	_gecis_kapali = false
	_son_gecis_pozisyonu = pos
	_son_blok_sayisi = bloklar.size()
	_gecis_alanini_guncelle(pos, bloklar)

func _gecis_alanini_guncelle(pos: Vector2, bloklar: Array) -> void:
	var r = TUTMA_YARICAPI + GECIS_GUNCELLEME_MESAFESI
	
	var raw_polys: Array[PackedVector2Array] = []
	
	# 1. Çöp adamın poligonu
	var s_rect = Rect2(pos.x - r, pos.y - 60 - GECIS_GUNCELLEME_MESAFESI, r * 2.0, 95.0 + GECIS_GUNCELLEME_MESAFESI * 2.0)
	raw_polys.append(PackedVector2Array([
		s_rect.position,
		Vector2(s_rect.end.x, s_rect.position.y),
		s_rect.end,
		Vector2(s_rect.position.x, s_rect.end.y)
	]))
	
	# 2. Blokların poligonları
	for blok in bloklar:
		var b_pos = blok.global_position
		var b_rect = Rect2(b_pos.x - 20, b_pos.y - 20, 40.0, 40.0)
		raw_polys.append(PackedVector2Array([
			b_rect.position,
			Vector2(b_rect.end.x, b_rect.position.y),
			b_rect.end,
			Vector2(b_rect.position.x, b_rect.end.y)
		]))
	
	# 3. Kesişen poligonları birleştir (Geometry2D ile)
	var merged_polys: Array[PackedVector2Array] = []
	for p in raw_polys:
		if merged_polys.is_empty():
			merged_polys.append(p)
		else:
			var new_merged: Array[PackedVector2Array] = []
			var to_merge = p
			for mp in merged_polys:
				var union_res = Geometry2D.merge_polygons(to_merge, mp)
				if union_res.size() == 1:
					to_merge = union_res[0] # Kesiştiler, birleştiler!
				else:
					new_merged.append(mp) # Kesişmediler
			new_merged.append(to_merge)
			merged_polys = new_merged
			
	# 4. Ayrık poligonları 0 piksellik görünmez çizgilerle tek poligona bağla
	var final_poly = PackedVector2Array()
	if merged_polys.size() > 0:
		final_poly.append_array(merged_polys[0])
		var base_point = merged_polys[0][0]
		for i in range(1, merged_polys.size()):
			var next_poly = merged_polys[i]
			final_poly.append(base_point)
			final_poly.append(next_poly[0])
			final_poly.append_array(next_poly)
			final_poly.append(next_poly[0])
			final_poly.append(base_point)
			
	DisplayServer.window_set_mouse_passthrough(final_poly)
# Fonksiyonu şimdi tanımlıyoruz
func haritayükle(dosyayolu: String) -> void:

	if not FileAccess.file_exists(dosyayolu):
		print("harita.json dosyası bulunamadı")
		return
		
	# Okuma modu
	var dosya = FileAccess.open(dosyayolu, FileAccess.READ)
	# Veriyi metine çeviriyor
	var metin = dosya.get_as_text()
	# Metni parse ettik
	var veri = JSON.parse_string(metin)
	
	print("harita okundu ikon sayısı:", veri["icons"].size())
	
	var ikonliste = veri["icons"]
	ikon_verileri = ikonliste  # Navigasyon sistemi için sakla
	
	for ikon in ikonliste:
		# Geçersiz veya dosya yolu olmayanları atlama
		if typeof(ikon["path"]) == TYPE_NIL or ikon["path"] == "":
			continue
		
		# Fiziksel obje yaratımı
		var zemin = StaticBody2D.new() # Sabit zemin
		var carpisma_alani = CollisionShape2D.new() # Çarpışma alanı
		var kutugeo = RectangleShape2D.new()
		
		var genislik = float(ikon["width"])
		var yukseklik = float(ikon["height"])
		kutugeo.size = Vector2(genislik, yukseklik)	
		
		carpisma_alani.shape = kutugeo # Şekli algılayıcıya taktık
		# Tek yönlü platform: içinden geçilir, sadece üstüne basılır
		carpisma_alani.one_way_collision = true
		carpisma_alani.one_way_collision_margin = 4.0
		zemin.collision_layer = 0
		zemin.set_collision_layer_value(IKON_KATMANI, true)
		zemin.add_to_group("ikonlar")
		
		var merkez_x = float(ikon["x"]) + (genislik / 2.0)
		var merkez_y = float(ikon["y"]) + (yukseklik / 2.0)
		zemin.position = Vector2(merkez_x, merkez_y)
		zemin.set_meta("hedef_dosya", ikon["path"])
		
		zemin.add_child(carpisma_alani)
		add_child(zemin)

# ============================================================
# AI NAVİGASYON DÖNGÜSÜ
# ============================================================

func _yeni_hedef_sec() -> void:
	if not otomatik_mod:
		print("Otomatik mod KAPALI. Manuel komut bekleniyor...")
		return
		
	var stickman = get_node_or_null("Stickman")
	if not stickman or not nav:
		return
	
	# --- %25 İHTİMALLE AYLAK DOLAŞMA ---
	if randf() < 0.25:
		_aylak_dolasmaya_basla(stickman)
		return
	
	# Normal hedef seçimi (son gidilen hedeflerden kaçın)
	var hedef = _tekrarsiz_hedef_sec()
	if hedef.is_empty():
		print("Gidilecek ikon bulunamadı!")
		hedef_zamanlayici.wait_time = 2.0
		hedef_zamanlayici.start()
		return
		
	print("Yeni hedef: ", hedef["isim"])
	
	# Son hedef listesine ekle
	son_hedefler.append(hedef["isim"])
	if son_hedefler.size() > SON_HEDEF_HAFIZA:
		son_hedefler.pop_front()
	
	if not stickman.hedefe_git(hedef["isim"]):
		hedef_zamanlayici.wait_time = 1.0
		hedef_zamanlayici.start()

func _tekrarsiz_hedef_sec() -> Dictionary:
	"""Son gidilen hedefleri atla, farklı bir hedef seç."""
	var tum_hedefler: Array = nav.hedefler()
	
	if tum_hedefler.is_empty():
		return {}
	
	# Son gidilen hedefleri filtrele
	var filtreli: Array = []
	for h in tum_hedefler:
		if h["isim"] not in son_hedefler:
			filtreli.append(h)
	
	# Eğer tüm hedefler son gidilenler arasındaysa, filtre olmadan seç
	if filtreli.is_empty():
		filtreli = tum_hedefler
	
	return filtreli[randi() % filtreli.size()]

func _aylak_dolasmaya_basla(stickman) -> void:
	"""Hedefsiz, üstünde durduğu yüzeyde rastgele ileri-geri yürü."""
	var mesafe = randf_range(200.0, 500.0) * (1 if randf() > 0.5 else -1)
	# Varınca rota_tamamlandi ile normal bekleme döngüsüne döner
	if not stickman.aylak_yuru(mesafe):
		hedef_zamanlayici.wait_time = 0.5
		hedef_zamanlayici.start()

func _firlatmadan_kurtuldu() -> void:
	if otomatik_mod and not tutulmus:
		hedef_zamanlayici.wait_time = FIRLATMA_SONRASI_BEKLEME
		hedef_zamanlayici.start()

func _hedefe_varildi() -> void:
	print("Hedefe ulaşıldı! Bekleniyor...")
	if otomatik_mod:
		var bekleme = randf_range(HEDEF_BEKLEME_SURESI_MIN, HEDEF_BEKLEME_SURESI_MAX)
		hedef_zamanlayici.wait_time = bekleme
		hedef_zamanlayici.start()

# ============================================================
# MANUEL HEDEFLEME (Sürükle & Bırak)
# ============================================================

func _input(event: InputEvent) -> void:
	var stickman = get_node_or_null("Stickman")
	if not stickman:
		return

	# "M" tuşuna basarak modu değiştir
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_M:
			otomatik_mod = not otomatik_mod
			print("--- MOD DEĞİŞTİ ---")
			if otomatik_mod:
				print("OTOMATİK HEDEF MODU: AÇIK")
				_yeni_hedef_sec()
			else:
				print("MANUEL MOD: AÇIK (Sürükle-bırak bekleniyor)")
				stickman.plani_iptal()
				hedef_zamanlayici.stop()
				
	# Sol tık: tut, savur, bırakınca fırlat
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if not surukleniyor and event.position.distance_to(stickman.global_position) < TUTMA_YARICAPI:
				tutulmus = true
				hedef_zamanlayici.stop()
				stickman.yakala()
		elif tutulmus:
			tutulmus = false
			stickman.birak()

	# Sağ tık: sürükleyip bırakarak hedef göster
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed:
			if not tutulmus and event.position.distance_to(stickman.global_position) < TUTMA_YARICAPI:
				surukleniyor = true
				fare_pozisyonu = event.position
				hedef_zamanlayici.stop()  # Rastgele dolaşmayı durdur
				otomatik_mod = false      # Elle sürüklenince otomatik modu kapat
				print("Manuel hedefleme başladı... (Otomatik mod Kapatıldı)")
		else:
			if surukleniyor:
				surukleniyor = false
				_manuel_hedef_belirle(event.position)
				queue_redraw()

	# Fare Hareketi
	elif event is InputEventMouseMotion and surukleniyor:
		fare_pozisyonu = event.position
		queue_redraw()  # Çizgiyi güncelle

func _draw() -> void:
	# Sürüklenirken hedefe nişan alma çizgisi çiz
	if surukleniyor:
		var stickman = get_node_or_null("Stickman")
		if stickman:
			# Kesik/noktalı çizgi efekti veya düz kırmızı çizgi
			draw_line(stickman.global_position, fare_pozisyonu, Color(1.0, 0.2, 0.2, 0.8), 4.0)
			draw_circle(fare_pozisyonu, 10.0, Color(1.0, 0.2, 0.2, 0.8))

func _manuel_hedef_belirle(birakma_noktasi: Vector2) -> void:
	if not nav: return
	var stickman = get_node_or_null("Stickman")
	if not stickman: return

	# Bırakılan noktaya en yakın platformu bul
	var en_yakin_isim = ""
	var min_mesafe = 999999.0
	
	# Görev çubuğunu da seçebilsin
	for s in nav.yuzeyler:
		var en_yakin_nokta = Vector2(clampf(birakma_noktasi.x, s["x0"], s["x1"]),
				clampf(birakma_noktasi.y, s["y"], s["y"] + s["h"]))
		var mesafe = birakma_noktasi.distance_to(en_yakin_nokta)
		if mesafe < min_mesafe:
			min_mesafe = mesafe
			en_yakin_isim = s["isim"]
			
	if en_yakin_isim != "":
		print("Manuel hedef: ", en_yakin_isim)
		stickman.hedefe_git(en_yakin_isim)

# ============================================================
# İNŞAAT (BUILDER) SİSTEMİ
# ============================================================

func _blok_yerlestir(pozisyon: Vector2) -> void:
	var blok = KiritasBlok.new()
	blok.position = pozisyon
	# Bloğu sahneye ekliyoruz
	add_child(blok)
	print("Kırıktaş yerleştirildi: ", pozisyon)
