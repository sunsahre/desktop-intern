extends Node2D

# --- NAVİGASYON SİSTEMİ ---
var nav: Navigasyon = null
var ikon_verileri: Array = []  # harita.json'dan okunan ikon listesi
var hedef_zamanlayici: Timer = null
const HEDEF_BEKLEME_SURESI = 5.0  # Hedefe varınca kaç sn bekle

# Modlar
@export var otomatik_mod: bool = true # True=Kendi gezer, False=Fareyle komut bekler

# --- MANUEL HEDEFLEME (Sürükle & Bırak) ---
var surukleniyor: bool = false
var fare_pozisyonu: Vector2 = Vector2.ZERO

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
		stickman.OYUNCU_KONTROLU = false  # AI kontrolüne geç
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
	if stickman_node:
		var pos = stickman_node.global_position
		var r = 50.0  # Tıklanabilir alan yarıçapı
		
		var raw_polys: Array[PackedVector2Array] = []
		
		# 1. Çöp adamın poligonu
		var s_rect = Rect2(pos.x - r, pos.y - 60, r * 2.0, 95.0)
		raw_polys.append(PackedVector2Array([
			s_rect.position,
			Vector2(s_rect.end.x, s_rect.position.y),
			s_rect.end,
			Vector2(s_rect.position.x, s_rect.end.y)
		]))
		
		# 2. Blokların poligonları
		var bloklar = get_tree().get_nodes_in_group("bloklar")
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
		
	var hedef = nav.rastgele_hedef_sec()
	if hedef.is_empty():
		print("Gidilecek ikon bulunamadı!")
		hedef_zamanlayici.wait_time = 2.0
		hedef_zamanlayici.start()
		return
		
	print("Yeni hedef: ", hedef["isim"])
	var rota = nav.yol_bul(stickman.global_position, hedef["isim"])
	
	if rota.size() > 0:
		# A* rota buldu, normal yürü/zıpla
		stickman.rotayi_ayarla(rota)
	else:
		# A* rota bulamadı → İNŞAAT MODU
		# Hedefin pozisyonunu al, inşaat moduna geç
		var hedef_pos = nav.hedef_pozisyon_bul(hedef["isim"])
		if hedef_pos != Vector2.ZERO:
			stickman.insaat_baslat(hedef["isim"], hedef_pos)
		else:
			hedef_zamanlayici.wait_time = 1.0
			hedef_zamanlayici.start()

func _hedefe_varildi() -> void:
	print("Hedefe ulaşıldı! Bekleniyor...")
	if otomatik_mod:
		hedef_zamanlayici.wait_time = HEDEF_BEKLEME_SURESI
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
				stickman.ai_stop()
				stickman.hedef_rota.clear()
				hedef_zamanlayici.stop()
				
	# Fare Tıklaması
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			# Stickman'e tıklandı mı? (50 piksel yakınlık)
			if event.position.distance_to(stickman.global_position) < 50.0:
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
	
	for id in nav.platformlar:
		var p = nav.platformlar[id]
		# Görev çubuğunu da seçebilsin
		var mesafe = birakma_noktasi.distance_to(p["pozisyon"])
		if mesafe < min_mesafe:
			min_mesafe = mesafe
			en_yakin_isim = p["isim"]
			
	if en_yakin_isim != "":
		print("Manuel hedef: ", en_yakin_isim)
		var rota = nav.yol_bul(stickman.global_position, en_yakin_isim)
		if rota.size() > 0:
			stickman.rotayi_ayarla(rota)
		else:
			# Ulaşım yoksa nerd-poling moduna gir
			var hedef_pos = nav.hedef_pozisyon_bul(en_yakin_isim)
			if hedef_pos != Vector2.ZERO:
				stickman.insaat_baslat(en_yakin_isim, hedef_pos)

# ============================================================
# İNŞAAT (BUILDER) SİSTEMİ
# ============================================================

func _blok_yerlestir(pozisyon: Vector2) -> void:
	var blok = KiritasBlok.new()
	blok.position = pozisyon
	# Bloğu sahneye ekliyoruz
	add_child(blok)
	print("Kırıktaş yerleştirildi: ", pozisyon)
