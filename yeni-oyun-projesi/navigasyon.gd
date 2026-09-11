extends RefCounted
class_name Navigasyon

# ============================================================
# A* PLATFORMER NAVİGASYON SİSTEMİ v2
# Görev çubuğu temel yol olarak kullanılır.
# İkonların ÜZERİNE çıkmak: alttan yürüyüp kenarından tırmanarak.
# ============================================================

var astar := AStar2D.new()
var platformlar: Dictionary = {}
var platform_sayaci: int = 0

# Fizik sabitleri (stickman.gd ile eşleşmeli)
const ZIPLAMA_HIZI := 287.0
const YERCEKIMI := 980.0
const YURUME_HIZI := 300.0

# Hesaplanan limitler
var max_ziplama_yuksekligi: float
var max_yatay_ziplama: float

func _init() -> void:
	max_ziplama_yuksekligi = (ZIPLAMA_HIZI * ZIPLAMA_HIZI) / (2.0 * YERCEKIMI)
	var havada_sure = 2.0 * (ZIPLAMA_HIZI / YERCEKIMI)
	max_yatay_ziplama = YURUME_HIZI * havada_sure
	print("Nav: max zıplama=", snapped(max_ziplama_yuksekligi, 1), "px, max yatay=", snapped(max_yatay_ziplama, 1), "px")


func grafi_kur(ikon_listesi: Array, ekran_boyutu: Vector2i) -> void:
	astar.clear()
	platformlar.clear()
	platform_sayaci = 0
	
	# 1. Görev çubuğu boyunca düğümler ekle (ANA KORIDOR)
	# Çöp adam çoğu yere görev çubuğu üzerinden yürüyerek gidecek
	var cubuk_y = float(ekran_boyutu.y) - 50.0
	var adim = 100.0
	var x = adim / 2.0
	while x < float(ekran_boyutu.x):
		_platform_ekle(Vector2(x, cubuk_y), "gorev_cubugu", "", adim)
		x += adim
	
	# 2. Her ikon için bir platform düğümü ekle
	# Stickman ikonun ÜZERİNDE durur, yani durak_y = ikon.y (üst kenar)
	# Ama fiziksel platform merkezi = ikon.y + height/2
	# Stickman'ın ayakları platformun üst kenarına denk gelir
	for ikon in ikon_listesi:
		if typeof(ikon["path"]) == TYPE_NIL or ikon["path"] == "":
			continue
		
		var genislik = float(ikon["width"])
		var yukseklik = float(ikon["height"])
		
		# Stickman'ın ayağının duracağı yer = platformun üst kenarı
		# Platform merkezi = ikon.y + height/2, üst kenarı = ikon.y
		var durak_x = float(ikon["x"]) + genislik / 2.0
		var durak_y = float(ikon["y"])  # Üst kenar = stickman'ın ayağı buraya basar
		
		_platform_ekle(Vector2(durak_x, durak_y), ikon.get("name", "bilinmeyen"), ikon.get("path", ""), genislik)
	
	# 3. Kenarları oluştur
	_kenarlari_olustur()
	print("Nav: ", platform_sayaci, " düğüm, graf hazır!")


func _platform_ekle(pozisyon: Vector2, isim: String, yol: String, genislik: float) -> int:
	var id = platform_sayaci
	platform_sayaci += 1
	astar.add_point(id, pozisyon)
	platformlar[id] = {
		"pozisyon": pozisyon,
		"isim": isim,
		"yol": yol,
		"genislik": genislik,
	}
	return id


func _kenarlari_olustur() -> void:
	var idler = astar.get_point_ids()
	for i in range(idler.size()):
		for j in range(i + 1, idler.size()):
			var id_a = idler[i]
			var id_b = idler[j]
			var pos_a = astar.get_point_position(id_a)
			var pos_b = astar.get_point_position(id_b)
			
			var dx = abs(pos_b.x - pos_a.x)
			var dy = pos_b.y - pos_a.y  # Pozitif = B aşağıda
			
			# Görev çubuğu düğümleri birbirine bağlansın (yatay koridor)
			var a_cubuk = platformlar[id_a]["isim"] == "gorev_cubugu"
			var b_cubuk = platformlar[id_b]["isim"] == "gorev_cubugu"
			
			if a_cubuk and b_cubuk:
				# Yan yana görev çubuğu düğümleri
				if dx <= 150:
					astar.connect_points(id_a, id_b)
				continue
			
			# Görev çubuğu <-> ikon bağlantısı
			# İkon görev çubuğunun üstünde, yatay olarak yakınsa bağla
			if (a_cubuk or b_cubuk):
				if dx < 120:
					astar.connect_points(id_a, id_b)
				continue
			
			# İkon <-> İkon bağlantısı
			if _eriselebilir_mi(dx, dy):
				astar.connect_points(id_a, id_b)


func _eriselebilir_mi(dx: float, dy: float) -> bool:
	# Çok uzak
	if dx > max_yatay_ziplama:
		return false
	
	# Aynı seviye ve yakın (yürüyerek)
	if abs(dy) < 40 and dx < 150:
		return true
	
	# Yukarı zıplama
	if dy < 0:
		if abs(dy) <= max_ziplama_yuksekligi * 0.7 and dx <= max_yatay_ziplama * 0.7:
			return true
	
	# Aşağı düşme
	if dy > 0:
		var dusme_suresi = sqrt(2.0 * abs(dy) / YERCEKIMI)
		var max_yatay_dusme = YURUME_HIZI * dusme_suresi
		if dx <= max_yatay_dusme:
			return true
	
	return false


# ============================================================
# YOL BULMA
# ============================================================

func yol_bul(baslangic: Vector2, hedef_ikon_adi: String) -> Array:
	var baslangic_id = astar.get_closest_point(baslangic)
	
	var hedef_id = -1
	for id in platformlar:
		if platformlar[id]["isim"] == hedef_ikon_adi:
			hedef_id = id
			break
	
	if hedef_id == -1:
		print("Nav HATA: '", hedef_ikon_adi, "' bulunamadı!")
		return []
	
	var yol_idleri = astar.get_id_path(baslangic_id, hedef_id)
	if yol_idleri.is_empty():
		print("Nav: Yol bulunamadı! (bağlantı yok)")
		return []
	
	var yol: Array = []
	for id in yol_idleri:
		yol.append(astar.get_point_position(id))
	
	print("Nav: Rota bulundu, ", yol.size(), " adım")
	return yol


func rastgele_hedef_sec() -> Dictionary:
	var ikon_platformlar: Array = []
	for id in platformlar:
		if platformlar[id]["isim"] != "gorev_cubugu" and platformlar[id]["yol"] != "":
			ikon_platformlar.append(platformlar[id])
	
	if ikon_platformlar.is_empty():
		return {}
	
	return ikon_platformlar[randi() % ikon_platformlar.size()]


func hedef_pozisyon_bul(hedef_isim: String) -> Vector2:
	"""İsme göre hedefin pozisyonunu döndürür."""
	for id in platformlar:
		if platformlar[id]["isim"] == hedef_isim:
			return platformlar[id]["pozisyon"]
	return Vector2.ZERO
