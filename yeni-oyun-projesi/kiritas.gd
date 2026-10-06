extends StaticBody2D
class_name KiritasBlok

const BOYUT: float = 40.0
const DOKU_KLASORU: String = "res://mc_doku/"
const KIRILMA_SURESI: float = 5.0    # Ömrün son kaç saniyesinde çatlamaya başlar
const RAGDOLL_KATMANI: int = 4       # Sadece savrulan ragdoll'un gördüğü katı kopya

var omur_sayaci: float = 30.0
var max_omur: float = 30.0
var kirilma: Sprite2D

# Dokular bir kez yüklenip tüm bloklarca paylaşılır
static var _kiritas_doku: Texture2D
static var _kirilma_dokulari: Array[Texture2D] = []
static var _dokular_yuklendi: bool = false

func _ready() -> void:
	add_to_group("bloklar")
	
	# 1. Fiziksel Çarpışma Alanı (40x40 Piksel Kutu)
	var sekil = CollisionShape2D.new()
	var dikdortgen = RectangleShape2D.new()
	dikdortgen.size = Vector2(BOYUT, BOYUT)
	sekil.shape = dikdortgen
	# İkonlar gibi tek yönlü: kuleler/köprüler yolu duvar gibi kapatmasın
	sekil.one_way_collision = true
	sekil.one_way_collision_margin = 4.0
	add_child(sekil)
	collision_layer = 0
	set_collision_layer_value(3, true)
	ragdoll_govdesi_ekle(self, dikdortgen.size)
	
	_dokulari_yukle()
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST  # Minecraft gibi keskin pikseller
	
	# 2. Görsel: Minecraft kırıktaş dokusu (yoksa düz gri kutu)
	if _kiritas_doku:
		var gorsel = Sprite2D.new()
		gorsel.texture = _kiritas_doku
		gorsel.scale = Vector2.ONE * BOYUT / _kiritas_doku.get_width()
		add_child(gorsel)
	else:
		var gri = ColorRect.new()
		gri.color = Color(0.5, 0.5, 0.5)
		gri.size = Vector2(BOYUT, BOYUT)
		gri.position = -Vector2(BOYUT, BOYUT) / 2.0
		add_child(gri)
	
	# 3. Kırılma çatlakları (Minecraft'taki destroy_stage aşamaları)
	kirilma = Sprite2D.new()
	kirilma.modulate = Color(0.12, 0.12, 0.12, 0.85)
	kirilma.visible = false
	add_child(kirilma)
	
	z_index = 5
	set_process(true)
	print("BLOK OLUŞTU: pos=", position)

static func ragdoll_govdesi_ekle(ebeveyn: Node2D, boyut: Vector2) -> void:
	"""Tek yönlü şekiller ışın sorgularında yandan/alttan görünmez; savrulan stickman
	ikon ve bloklara her yönden çarpsın diye ayrı katmanda katı bir kopya eklenir."""
	var govde = StaticBody2D.new()
	govde.collision_layer = 0
	govde.collision_mask = 0
	govde.set_collision_layer_value(RAGDOLL_KATMANI, true)
	var sekil = CollisionShape2D.new()
	var kutu = RectangleShape2D.new()
	kutu.size = boyut
	sekil.shape = kutu
	govde.add_child(sekil)
	ebeveyn.add_child(govde)

static func _dokulari_yukle() -> void:
	if _dokular_yuklendi:
		return
	_dokular_yuklendi = true
	_kiritas_doku = _png_yukle(DOKU_KLASORU + "cobblestone.png")
	for i in 10:
		var doku := _png_yukle(DOKU_KLASORU + "destroy_stage_%d.png" % i)
		if doku:
			_kirilma_dokulari.append(doku)

static func _png_yukle(yol: String) -> Texture2D:
	# İçe aktarılmamış (git'e girmeyen) PNG'leri doğrudan dosyadan okur
	var tam_yol := ProjectSettings.globalize_path(yol)
	if not FileAccess.file_exists(tam_yol):
		return null
	var resim := Image.load_from_file(tam_yol)
	return ImageTexture.create_from_image(resim) if resim else null

func _process(delta: float) -> void:
	omur_sayaci -= delta
	
	if omur_sayaci <= 0:
		queue_free()
	elif omur_sayaci < KIRILMA_SURESI:
		_kirilma_guncelle()

func _kirilma_guncelle() -> void:
	if _kirilma_dokulari.is_empty():
		return
	var ilerleme: float = 1.0 - omur_sayaci / KIRILMA_SURESI
	var asama: int = clampi(int(ilerleme * _kirilma_dokulari.size()), 0, _kirilma_dokulari.size() - 1)
	kirilma.texture = _kirilma_dokulari[asama]
	kirilma.scale = Vector2.ONE * BOYUT / kirilma.texture.get_width()
	kirilma.visible = true
