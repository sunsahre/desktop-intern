extends Node2D

# Called when the node enters the scene tree for the first time.
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
	
	# 4. KİLİT NOKTA: Tıklama geçirme komutu KESİNLİKLE boyutlandırmadan sonra olmalı!
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_MOUSE_PASSTHROUGH, true)
	# ------------------------------------

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
