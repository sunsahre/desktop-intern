extends PanelContainer
class_name KomutPaneli
## Stickman'e komut verilen açılır pencere. "," tuşu (ya da stickman'e orta tık) ile açılıp kapanır.

signal komut_secildi(komut: String, hedef: Dictionary)

const TURUNCU := Color(1.0, 0.43, 0.0)

var _hedefler: Array = []
var _gorunen: Array = []          # Arama filtresinden geçen hedefler (listedeki sırayla)
var _arama: LineEdit
var _liste: ItemList
var _git_btn: Button
var _git_ac_btn: Button
var _hemen_ac_btn: Button
var _otomatik_btn: Button
var _durum: Label

func _ready() -> void:
	visible = false
	custom_minimum_size = Vector2(320, 0)
	add_theme_stylebox_override("panel", _kutu_stili(Color(0.09, 0.09, 0.11, 0.96), TURUNCU, 10))
	
	var kenar := MarginContainer.new()
	for yon in ["left", "right", "top", "bottom"]:
		kenar.add_theme_constant_override("margin_" + yon, 12)
	add_child(kenar)
	var dikey := VBoxContainer.new()
	dikey.add_theme_constant_override("separation", 8)
	kenar.add_child(dikey)
	
	# Başlık
	var baslik_satiri := HBoxContainer.new()
	var baslik := Label.new()
	baslik.text = "Stickman Komutları"
	baslik.add_theme_color_override("font_color", TURUNCU)
	baslik.add_theme_font_size_override("font_size", 17)
	baslik.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	baslik_satiri.add_child(baslik)
	var kapat := Button.new()
	kapat.text = "✕"
	kapat.flat = true
	kapat.tooltip_text = "Kapat ( , )"
	kapat.pressed.connect(func(): visible = false)
	baslik_satiri.add_child(kapat)
	dikey.add_child(baslik_satiri)
	
	# Hedef seçimi
	_arama = LineEdit.new()
	_arama.placeholder_text = "Hedef ara..."
	_arama.clear_button_enabled = true
	_arama.text_changed.connect(func(_t): _listeyi_doldur())
	_arama.text_submitted.connect(_arama_onaylandi)
	dikey.add_child(_arama)
	
	_liste = ItemList.new()
	_liste.custom_minimum_size = Vector2(0, 210)
	_liste.item_selected.connect(func(_i): _butonlari_guncelle())
	_liste.item_activated.connect(func(_i): _hedef_komutu("git_ac"))
	dikey.add_child(_liste)
	
	var hedef_satiri := HBoxContainer.new()
	_git_btn = _buton("Git", "Seçili hedefe yürür", func(): _hedef_komutu("git"))
	_git_ac_btn = _buton("Git ve aç", "Seçili hedefe yürür, varınca dosyayı açar", func(): _hedef_komutu("git_ac"))
	_hemen_ac_btn = _buton("Hemen aç", "Yürümeden dosyayı açar", func(): _hedef_komutu("hemen_ac"))
	for b in [_git_btn, _git_ac_btn, _hemen_ac_btn]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hedef_satiri.add_child(b)
	_git_ac_btn.add_theme_stylebox_override("normal", _kutu_stili(TURUNCU.darkened(0.35), TURUNCU, 4))
	dikey.add_child(hedef_satiri)
	
	dikey.add_child(HSeparator.new())
	
	# Genel komutlar
	var izgara := GridContainer.new()
	izgara.columns = 2
	izgara.add_theme_constant_override("h_separation", 6)
	izgara.add_theme_constant_override("v_separation", 6)
	_otomatik_btn = _buton("Rastgele gez: Açık", "Kendi kendine hedef seçip gezmesini aç/kapat (M)", func(): komut_secildi.emit("otomatik", {}))
	for b in [
		_buton("Dur", "Yaptığı işi bırakıp durur", func(): komut_secildi.emit("dur", {})),
		_otomatik_btn,
		_buton("Görev çubuğuna in", "Görev çubuğuna iner", func(): komut_secildi.emit("gorev_cubugu", {})),
		_buton("Zıpla", "Olduğu yerde zıplar", func(): komut_secildi.emit("zipla", {})),
		_buton("Blokları temizle", "Koyduğu tüm kırıktaşları kaldırır", func(): komut_secildi.emit("bloklari_temizle", {})),
		_buton("Masaüstünü yenile", "İkon listesini yeniden okur", func(): komut_secildi.emit("yenile", {})),
	]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		izgara.add_child(b)
	dikey.add_child(izgara)
	
	_durum = Label.new()
	_durum.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_durum.custom_minimum_size = Vector2(296, 0)  # Genişliksiz kaydırmalı etiket paneli boyuna uzatıyor
	_durum.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	_durum.text = "Bir hedef seç."
	dikey.add_child(_durum)
	
	var ipucu := Label.new()
	ipucu.text = "\",\" ile aç/kapat  ·  çift tık: git ve aç"
	ipucu.add_theme_font_size_override("font_size", 11)
	ipucu.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
	dikey.add_child(ipucu)
	
	_butonlari_guncelle()

func hedefleri_ayarla(liste: Array) -> void:
	_hedefler = liste.duplicate()
	_hedefler.sort_custom(func(a, b): return a["isim"].naturalnocasecmp_to(b["isim"]) < 0)
	if is_node_ready():
		_listeyi_doldur()

func otomatik_ayarla(acik: bool) -> void:
	_otomatik_btn.text = "Rastgele gez: " + ("Açık" if acik else "Kapalı")

func durum_yaz(metin: String) -> void:
	_durum.text = metin

func ac(konum: Vector2) -> void:
	_listeyi_doldur()
	visible = true
	reset_size()
	var ekran: Vector2 = get_viewport_rect().size
	position = Vector2(clampf(konum.x, 8.0, ekran.x - size.x - 8.0), clampf(konum.y, 8.0, ekran.y - size.y - 58.0))
	_arama.grab_focus()
	_arama.select_all()

func _listeyi_doldur() -> void:
	var secili: String = _secili_hedef().get("isim", "")
	var filtre: String = _arama.text.strip_edges().to_lower()
	_liste.clear()
	_gorunen.clear()
	for h in _hedefler:
		if filtre == "" or filtre in String(h["isim"]).to_lower():
			_gorunen.append(h)
			_liste.add_item(h["isim"])
			_liste.set_item_tooltip(_liste.item_count - 1, h["yol"])
			if h["isim"] == secili:
				_liste.select(_liste.item_count - 1)
	_butonlari_guncelle()

func _secili_hedef() -> Dictionary:
	var secim := _liste.get_selected_items()
	if secim.is_empty() or secim[0] >= _gorunen.size():
		return {}
	return _gorunen[secim[0]]

func _hedef_komutu(komut: String) -> void:
	var hedef := _secili_hedef()
	if not hedef.is_empty():
		komut_secildi.emit(komut, hedef)

func _arama_onaylandi(_metin: String) -> void:
	if _secili_hedef().is_empty() and not _gorunen.is_empty():
		_liste.select(0)
	_hedef_komutu("git_ac")

func _butonlari_guncelle() -> void:
	var yok := _secili_hedef().is_empty()
	for b in [_git_btn, _git_ac_btn, _hemen_ac_btn]:
		b.disabled = yok

func _buton(metin: String, ipucu: String, eylem: Callable) -> Button:
	var b := Button.new()
	b.text = metin
	b.tooltip_text = ipucu
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(eylem)
	return b

static func _kutu_stili(dolgu: Color, kenar: Color, yaricap: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = dolgu
	s.border_color = kenar
	s.set_border_width_all(2 if yaricap > 6 else 1)
	s.set_corner_radius_all(yaricap)
	s.content_margin_left = 8
	s.content_margin_right = 8
	s.content_margin_top = 4
	s.content_margin_bottom = 4
	return s
