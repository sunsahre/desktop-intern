extends StaticBody2D
class_name KiritasBlok

var omur_sayaci: float = 30.0
var max_omur: float = 30.0
var ana_renk: ColorRect
var kirilma_cizgileri: Node2D

func _ready() -> void:
	add_to_group("bloklar")
	
	# 1. Fiziksel Çarpışma Alanı (40x40 Piksel Kutu)
	var sekil = CollisionShape2D.new()
	var dikdortgen = RectangleShape2D.new()
	dikdortgen.size = Vector2(40, 40)
	sekil.shape = dikdortgen
	add_child(sekil)
	
	# 2. Görsel: Ana Gri Kutu (ColorRect)
	ana_renk = ColorRect.new()
	ana_renk.color = Color(0.5, 0.5, 0.5)
	ana_renk.size = Vector2(40, 40)
	ana_renk.position = Vector2(-20, -20)
	add_child(ana_renk)
	
	# Dokular (Çizgiler) - Koyu gri küçük kutularla doku yapalım
	for pos in [Vector2(5, 5), Vector2(25, 10), Vector2(10, 25), Vector2(25, 25)]:
		var doku = ColorRect.new()
		doku.color = Color(0.3, 0.3, 0.3)
		doku.size = Vector2(8, 4)
		doku.position = pos
		ana_renk.add_child(doku)
		
	# Çerçeve
	var cerceve = ReferenceRect.new()
	cerceve.editor_only = false
	cerceve.border_color = Color(0.2, 0.2, 0.2)
	cerceve.border_width = 2.0
	cerceve.size = Vector2(40, 40)
	ana_renk.add_child(cerceve)
	
	# Kırılma efektlerini tutacak Node
	kirilma_cizgileri = Node2D.new()
	add_child(kirilma_cizgileri)
	
	z_index = 5
	set_process(true)
	print("BLOK OLUŞTU: pos=", position)

func _process(delta: float) -> void:
	omur_sayaci -= delta
	
	if omur_sayaci <= 0:
		queue_free()
	elif omur_sayaci < 5.0:
		_kirilma_guncelle()

func _kirilma_guncelle() -> void:
	# Eski kırık çizgilerini temizle
	for child in kirilma_cizgileri.get_children():
		child.queue_free()
		
	var kirilma_seviyesi = 5.0 - omur_sayaci
	var catlak_rengi = Color.BLACK
	var c = kirilma_seviyesi * 4.0
	var offset = Vector2(randf_range(-1, 1), randf_range(-1, 1))
	
	# Çatlakları Line2D ile oluşturuyoruz
	if kirilma_seviyesi > 1.0:
		_catlak_ciz(Vector2(0,0) + offset, Vector2(-c, -c) + offset, catlak_rengi, 2)
	if kirilma_seviyesi > 2.0:
		_catlak_ciz(Vector2(0,0) + offset, Vector2(c, -c*0.5) + offset, catlak_rengi, 2)
	if kirilma_seviyesi > 3.0:
		_catlak_ciz(Vector2(0,0) + offset, Vector2(-c*0.5, c) + offset, catlak_rengi, 2)
	if kirilma_seviyesi > 4.0:
		_catlak_ciz(Vector2(-c*0.5, c) + offset, Vector2(c, c) + offset, catlak_rengi, 3)

func _catlak_ciz(bas: Vector2, son: Vector2, renk: Color, kalinlik: float) -> void:
	var cizgi = Line2D.new()
	cizgi.add_point(bas)
	cizgi.add_point(son)
	cizgi.default_color = renk
	cizgi.width = kalinlik
	kirilma_cizgileri.add_child(cizgi)

