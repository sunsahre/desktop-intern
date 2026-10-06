extends CharacterBody2D

# ============================================================
# ÇÖP ADAM (STICKMAN) - FİZİK VE ANİMASYON SİSTEMİ
# ============================================================

# --- HAREKET VE FİZİK AYARLARI ---
@export var SPEED: float = 300.0
@export var JUMP_VELOCITY: float = -287.0 # Zıplama tam 42 piksel yüksekliğinde (40px blok için 2px pay)
@export var GRAVITY_SCALE: float = 1.0
@export var OYUNCU_KONTROLU: bool = true # Klavye ile test etmek için Inspector'dan kapatıp açabilirsin

# --- AI VE KONTROL DEĞİŞKENLERİ ---
var move_direction: int = 0   # -1 = sol, 0 = dur, 1 = sağ
var should_jump: bool = false

# --- PLAN YÜRÜTÜCÜ (navigasyon.gd plan_yap çıktısı) ---
signal rota_tamamlandi            # Hedefe ulaşınca (ya da vazgeçince) sinyal gönder
var nav: Navigasyon = null        # Sahne atar
var plan: Array = []              # Adım listesi: YURU, ZIPLA, TIRMAN, DUS_IC, DUS_KENAR, KULE, KOPRU
var hedef_isim: String = ""
var _asama: int = 0               # Adımın iç aşaması
var _adim_suresi: float = 0.0     # Adımda geçen süre (takılma için)
var _dusunme: float = 0.0         # Zıplama/tırmanma öncesi kısa tereddüt
var _yeniden_plan_sayisi: int = 0
const MAX_YENIDEN_PLAN: int = 5
const AYAK: float = 31.0          # Gövde merkezinden ayak tabanına mesafe (kapsül)
const IKON_KATMANI: int = 3       # İkonlar ve bloklar (tek yönlü) bu fizik katmanında

# --- TIRMANMA MEKANİĞİ ---
const CLIMB_SPEED: float = 150.0   # Tırmanma hızı
const MAX_CLIMB_TIME: float = 0.8  # Kaç saniye aralıksız tırmanabilir
var climb_timer: float = 0.0       # Tırmanmaya harcanan süre
var tirmaniyor: bool = false       # Yürütücü tırmanma istiyor

# --- İÇİNDEN DÜŞME (tek yönlü platformdan aşağı süzülme) ---
var _gecis_y: float = INF          # Bu y'nin altına inene kadar ikon katmanı kapalı
var _gecis_suresi: float = 0.0

# --- İNŞAAT ---
var blok_bekleme: float = 0.0
const BLOK_BEKLEME_SURESI: float = 0.35
var insaat_anim: float = 0.0       # Blok koyarken kısa BUILD pozu
var _bu_ziplamada_koydum: bool = false
var _kule_taban: float = 0.0
var _kopru_uc: float = 0.0
signal blok_koy(pozisyon: Vector2) # Sahne.gd'ye blok koyması için sinyal gönderir

# --- DURUM (STATE) MAKİNESİ ---
enum State { IDLE, WALK, JUMP, FALL, CLIMB, BUILD, GRABBED, THROWN }
var current_state: State = State.IDLE
var facing_right: bool = true

# --- ÇİZİM VE KOZMETİK AYARLAR (Animation vs Minecraft Turuncu Stickman) ---
var body_color: Color = Color(1.0, 0.53, 0.0)    # Turuncu dolgu
var outline_color: Color = Color(0.8, 0.4, 0.0)  # Koyu turuncu çerçeve
var eye_color: Color = Color.BLACK
var line_width: float = 5.0  # Kalın çizgiler (AvM tarzı)

# Yerçekimini proje ayarlarından dinamik çekiyoruz
var gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")

# --- ZAMANLAYICILAR (Animasyonlar İçin) ---
var anim_time: float = 0.0
var breath_time: float = 0.0

# --- MOUSE İLE TUTMA / FIRLATMA ---
signal yakalandi
signal yere_indi                     # Fırlatıldıktan sonra yere inip kendine geldi
const TUTMA_NOKTASI: Vector2 = Vector2(0, -38)  # Kafanın tepesinden tutulur
const TUTMA_TAKIP: float = 30.0      # Fareye ne kadar sıkı yapışsın (büyük = daha sıkı)
const FIRLATMA_CARPANI: float = 1.2
const MAX_FIRLATMA_HIZI: float = 2200.0
const SEKME_KATSAYISI: float = 0.45  # Çarpınca hızın ne kadarı korunur
const SERSEMLEME_SURESI: float = 0.8
var is_grabbed: bool = false         # Şu an tutulmuş mu?
var is_thrown: bool = false          # Fırlatılmış mı? (yere düşene kadar)
var fare_hizi: Vector2 = Vector2.ZERO
var _onceki_fare: Vector2 = Vector2.ZERO
var _onceki_fare_hizi: Vector2 = Vector2.ZERO
var sallanma_aci: float = 0.0        # Tutulunca sarkaç açısı
var sallanma_hizi: float = 0.0
var donme_aci: float = 0.0           # Havada dönme açısı
var donme_hizi: float = 0.0
var sersem_suresi: float = 0.0

# --- İVMELİ HAREKET ---
const ZEMIN_IVME: float = 1600.0
const ZEMIN_FREN: float = 2200.0
const HAVA_IVME: float = 1000.0
var walk_phase: float = 0.0          # Yürüme döngüsü, gerçek hıza göre ilerler
var climb_phase: float = 0.0         # Tırmanma döngüsü, gerçek tırmanma hızına göre ilerler
var hava_suresi: float = 0.0         # Kenarlarda tek karelik "havada" titremesini filtreler

# --- DOĞAL HAREKET SİSTEMİ ---
var hiz_carpani: float = 1.0         # Anlık hız çarpanı (0.8 – 1.2 arası smooth)
var hiz_hedef: float = 1.0           # Hedef hız çarpanı
var hiz_degisim_zamani: float = 0.0  # Hız ne zaman değişecek
var durakla_zamanlayici: float = 0.0 # Yürürken duraklamalar
var duraksadi: bool = false          # Şu an duraklıyor mu?
var duraklama_suresi: float = 0.0    # Ne kadar duracak

# ============================================================
# 1. TEMEL DÖNGÜLER (FİZİK VE KONTROL)
# ============================================================

func _ready() -> void:
	floor_snap_length = 10.0
	set_collision_mask_value(IKON_KATMANI, true)

func _process(delta: float) -> void:
	# Görsel animasyonların zamanlayıcılarını güncelliyoruz
	anim_time += delta
	breath_time += delta
	
	# Yere inince dönme açısını yumuşakça sıfırla
	if not is_grabbed and not is_thrown and donme_aci != 0.0:
		donme_aci = lerp_angle(donme_aci, 0.0, minf(1.0, 12.0 * delta))
		if absf(donme_aci) < 0.01:
			donme_aci = 0.0
	
	# Doğal hız değişimi (smooth interpolation)
	_hiz_guncelle(delta)
	
	# Eğer klavye kontrolü açıksa, AI komutlarını klavye ile eziyoruz
	if OYUNCU_KONTROLU:
		_klavye_dinle()

func _physics_process(delta: float) -> void:
	if is_grabbed:
		_tutulma_fizigi(delta)
		queue_redraw()
		return
	
	if is_thrown:
		_firlatma_fizigi(delta)
		queue_redraw()
		return
	
	if sersem_suresi > 0.0:
		sersem_suresi -= delta
		if sersem_suresi <= 0.0:
			yere_indi.emit()
	
	var tirmandimi = false
	
	if blok_bekleme > 0:
		blok_bekleme -= delta
	if insaat_anim > 0:
		insaat_anim -= delta
	
	# --- KARAR (yürütücü move_direction / should_jump / tirmaniyor ayarlar) ---
	if not OYUNCU_KONTROLU and sersem_suresi <= 0.0:
		if duraksadi:
			duraklama_suresi -= delta
			if duraklama_suresi <= 0:
				duraksadi = false
			move_direction = 0
		else:
			_plan_yurut(delta)
			# Uzun yürüyüşlerde ara sıra durup etrafa bakar
			if move_direction != 0 and is_on_floor() and not plan.is_empty() and plan[0]["tip"] == "YURU":
				durakla_zamanlayici -= delta
				if durakla_zamanlayici <= 0:
					durakla_zamanlayici = randf_range(3.0, 8.0)
					if randf() < 0.12:
						duraksadi = true
						duraklama_suresi = randf_range(0.4, 1.2)
	
	# --- İÇİNDEN DÜŞME: ikonun üst kenarını geçince katmanı geri aç ---
	if _gecis_y < INF:
		_gecis_suresi -= delta
		if global_position.y + AYAK > _gecis_y + 8.0 or _gecis_suresi <= 0.0:
			_gecis_y = INF
			set_collision_mask_value(IKON_KATMANI, true)
	
	# --- DİKEY HAREKET & TIRMANMA ---
	if is_on_floor():
		# Tırmanma enerjisi ~1.2 saniyede dolar (sütun tırmanırken her ikonda kısa mola)
		if climb_timer > 0.0:
			climb_timer = max(0.0, climb_timer - delta * (MAX_CLIMB_TIME / 1.2))
		if should_jump:
			velocity.y = JUMP_VELOCITY
	
	# Zıplamanın ilk itişini koru, yavaşlayınca tırmanmaya geç (42px + ~120px)
	if tirmaniyor and not is_on_floor() and velocity.y >= -CLIMB_SPEED:
		if climb_timer < MAX_CLIMB_TIME:
			velocity.y = -CLIMB_SPEED
			climb_timer += delta
			tirmandimi = true
		else:
			tirmaniyor = false
	
	if not tirmandimi and not is_on_floor():
		velocity.y += gravity * GRAVITY_SCALE * delta
	
	should_jump = false
	
	if sersem_suresi > 0.0:
		move_direction = 0
	
	# Hıza anında değil, ivmeyle ulaş (ani başla/dur robotikliğini önler)
	var hedef_hiz: float = move_direction * SPEED * hiz_carpani
	var ivme: float = ZEMIN_IVME
	if not is_on_floor():
		ivme = HAVA_IVME
	elif move_direction == 0 or hedef_hiz * velocity.x < 0.0:
		ivme = ZEMIN_FREN
	velocity.x = move_toward(velocity.x, hedef_hiz, ivme * delta)
	
	# --- YÜZÜNÜ DÖNME ---
	if move_direction != 0:
		facing_right = move_direction > 0
	
	# Hareketi uygula
	move_and_slide()
	
	if is_on_floor():
		hava_suresi = 0.0
		walk_phase += absf(velocity.x) / SPEED * 9.0 * delta
	else:
		hava_suresi += delta
	if tirmandimi:
		climb_phase += absf(velocity.y) / CLIMB_SPEED * 7.0 * delta
	
	# --- DURUM (STATE) GÜNCELLEMESİ ---
	_durumu_belirle(tirmandimi)
	
	# Her fizik karesinde çizimi (animasyonu) yenile
	queue_redraw()

# ============================================================
# 2. YARDIMCI FONKSİYONLAR
# ============================================================

func _klavye_dinle() -> void:
	if Input.is_action_pressed("ui_right"):
		ai_move_right()
	elif Input.is_action_pressed("ui_left"):
		ai_move_left()
	else:
		ai_stop()
		
	if Input.is_action_just_pressed("ui_accept"): # Boşluk tuşu
		ai_jump()

func _durumu_belirle(tirmandimi: bool) -> void:
	if tirmandimi:
		current_state = State.CLIMB
	elif insaat_anim > 0.0:
		current_state = State.BUILD
	elif not is_on_floor() and (hava_suresi > 0.1 or velocity.y < -50.0):
		if velocity.y < 0:
			current_state = State.JUMP
		else:
			current_state = State.FALL
	elif absf(velocity.x) > 30.0:
		current_state = State.WALK
	else:
		current_state = State.IDLE

func _hiz_guncelle(delta: float) -> void:
	# Smooth hız değişimi — robotik sabit hız yerine doğal varyasyon
	hiz_degisim_zamani -= delta
	if hiz_degisim_zamani <= 0:
		hiz_hedef = randf_range(0.82, 1.18)  # ±18% hız varyasyonu
		hiz_degisim_zamani = randf_range(1.5, 4.0)  # 1.5–4 sn arası değişir
	# Yumuşak geçiş (lerp)
	hiz_carpani = lerp(hiz_carpani, hiz_hedef, delta * 2.0)

# --- MOUSE İLE TUTMA/FIRLATMA API ---
func yakala() -> void:
	"""Sahne.gd tarafından çağrılır — stickman'ı yakala."""
	is_grabbed = true
	is_thrown = false
	sersem_suresi = 0.0
	velocity = Vector2.ZERO
	move_direction = 0
	should_jump = false
	duraksadi = false
	current_state = State.GRABBED
	_onceki_fare = get_global_mouse_position()
	fare_hizi = Vector2.ZERO
	_onceki_fare_hizi = Vector2.ZERO
	sallanma_aci = 0.0
	sallanma_hizi = 0.0
	donme_aci = 0.0
	donme_hizi = 0.0
	plani_iptal()
	yakalandi.emit()

func birak() -> void:
	"""Fare bırakılınca çağrılır — farenin son hızıyla fırlatır."""
	if not is_grabbed:
		return
	is_grabbed = false
	is_thrown = true
	velocity = (fare_hizi * FIRLATMA_CARPANI).limit_length(MAX_FIRLATMA_HIZI)
	# Pivot etrafındaki sarkaç dönüşünü merkez etrafındaki dönüşe çevir (görsel sıçrama olmasın)
	move_and_collide(TUTMA_NOKTASI - TUTMA_NOKTASI.rotated(sallanma_aci))
	donme_aci = sallanma_aci
	donme_hizi = sallanma_hizi
	current_state = State.THROWN

func firlatma_bitti_mi() -> bool:
	return not is_grabbed and not is_thrown

func _tutulma_fizigi(delta: float) -> void:
	var fare: Vector2 = get_global_mouse_position()
	var anlik_hiz: Vector2 = (fare - _onceki_fare) / delta
	_onceki_fare = fare
	fare_hizi = fare_hizi.lerp(anlik_hiz, 0.4)
	var fare_ivmesi: Vector2 = (fare_hizi - _onceki_fare_hizi) / delta
	_onceki_fare_hizi = fare_hizi
	
	# Sarkaç: fare hızlanınca gövde geride kalır, sonra yerçekimiyle sallanıp durulur
	var savrulma: float = clampf(fare_ivmesi.x * 0.012, -250.0, 250.0)
	sallanma_hizi += (-sin(sallanma_aci) * 16.0 + savrulma * cos(sallanma_aci)) * delta
	sallanma_hizi *= exp(-2.5 * delta)
	sallanma_aci = clampf(sallanma_aci + sallanma_hizi * delta, -2.6, 2.6)
	
	if absf(fare_hizi.x) > 40.0:
		facing_right = fare_hizi.x > 0
	
	velocity = (fare - TUTMA_NOKTASI - global_position) * TUTMA_TAKIP
	move_and_slide()
	velocity = Vector2.ZERO
	current_state = State.GRABBED

func _firlatma_fizigi(delta: float) -> void:
	velocity.y += gravity * GRAVITY_SCALE * delta
	velocity *= exp(-0.3 * delta)  # Hafif hava direnci
	donme_hizi = lerpf(donme_hizi, velocity.x * 0.012, minf(1.0, 3.0 * delta))
	donme_aci += donme_hizi * delta
	current_state = State.THROWN
	
	var carpisma := move_and_collide(velocity * delta)
	if carpisma:
		var normal: Vector2 = carpisma.get_normal()
		if normal.y < -0.7 and absf(velocity.dot(normal)) < 300.0:
			_yere_kon()
			return
		velocity = velocity.bounce(normal) * SEKME_KATSAYISI
		donme_hizi *= -0.6
	
	_ekran_siniri()

func _yere_kon() -> void:
	is_thrown = false
	velocity.y = 0.0
	velocity.x *= 0.5
	donme_aci = wrapf(donme_aci, -PI, PI)
	donme_hizi = 0.0
	sersem_suresi = SERSEMLEME_SURESI
	current_state = State.IDLE

func _ekran_siniri() -> void:
	var ekran: Vector2 = get_viewport_rect().size
	if global_position.x < 20.0:
		global_position.x = 20.0
		velocity.x = absf(velocity.x) * SEKME_KATSAYISI
	elif global_position.x > ekran.x - 20.0:
		global_position.x = ekran.x - 20.0
		velocity.x = -absf(velocity.x) * SEKME_KATSAYISI
	if global_position.y < 45.0:
		global_position.y = 45.0
		velocity.y = absf(velocity.y) * SEKME_KATSAYISI

# ============================================================
# 3. ÇÖP ADAM ÇİZİM MOTORU (PROCEDURAL ANIMATION)
# ============================================================

func _draw() -> void:
	var dir: float = 1.0 if facing_right else -1.0
	
	if current_state == State.GRABBED:
		draw_set_transform_matrix(Transform2D(sallanma_aci, TUTMA_NOKTASI) * Transform2D(0.0, -TUTMA_NOKTASI))
	elif donme_aci != 0.0:
		draw_set_transform(Vector2.ZERO, donme_aci)
	
	match current_state:
		State.IDLE:
			_draw_idle(dir)
		State.WALK:
			_draw_walk(dir)
		State.JUMP:
			_draw_jump(dir)
		State.FALL:
			_draw_fall(dir)
		State.CLIMB:
			_draw_climb(dir)
		State.BUILD:
			_draw_build(dir)
		State.GRABBED:
			_draw_grabbed(dir)
		State.THROWN:
			_draw_thrown(dir)

func _draw_idle(dir: float) -> void:
	var nefes: float = sin(breath_time * 2.0) * 1.5
	
	# BACAKLAR
	var kalca: Vector2 = Vector2(0, 5 + nefes)
	var sol_diz: Vector2 = Vector2(-6, 16 + nefes * 0.5)
	var sol_ayak: Vector2 = Vector2(-8, 27)
	var sag_diz: Vector2 = Vector2(6, 16 + nefes * 0.5)
	var sag_ayak: Vector2 = Vector2(8, 27)
	
	draw_line(kalca, sol_diz, outline_color, line_width)
	draw_line(sol_diz, sol_ayak, outline_color, line_width)
	draw_line(kalca, sag_diz, outline_color, line_width)
	draw_line(sag_diz, sag_ayak, outline_color, line_width)
	
	# GÖVDE
	var bel: Vector2 = Vector2(0, 5 + nefes)
	var omuz: Vector2 = Vector2(0, -18 + nefes)
	draw_line(bel, omuz, outline_color, line_width)
	
	# KOLLAR
	var kol_sallanma: float = sin(breath_time * 1.5) * 3.0
	var sol_dirsek: Vector2 = Vector2(-10, -8 + nefes + kol_sallanma)
	var sol_el: Vector2 = Vector2(-12, 2 + nefes + kol_sallanma * 0.5)
	var sag_dirsek: Vector2 = Vector2(10, -8 + nefes - kol_sallanma)
	var sag_el: Vector2 = Vector2(12, 2 + nefes - kol_sallanma * 0.5)
	
	draw_line(omuz, sol_dirsek, outline_color, line_width)
	draw_line(sol_dirsek, sol_el, outline_color, line_width)
	draw_line(omuz, sag_dirsek, outline_color, line_width)
	draw_line(sag_dirsek, sag_el, outline_color, line_width)
	
	# KAFA VE YÜZ (AvM tarzı: turuncu dolgu + koyu çerçeve)
	var kafa_merkez: Vector2 = Vector2(0, -28 + nefes)
	draw_circle(kafa_merkez, 12.0, outline_color)  # Koyu çerçeve
	draw_circle(kafa_merkez, 10.0, body_color)      # Turuncu dolgu
	draw_circle(kafa_merkez + Vector2(3.0 * dir, -2), 1.8, eye_color) # Göz
	
	var agiz_merkez: Vector2 = kafa_merkez + Vector2(2.0 * dir, 3)
	draw_arc(agiz_merkez, 3.0, 0.2, PI - 0.2, 12, outline_color, 1.5) # Gülümseme

# --- IK YARDIMCILARI ---
const UYLUK: float = 12.5
const BALDIR: float = 12.5
const PAZU: float = 10.0
const ONKOL: float = 10.0

func _eklem_bul(kok: Vector2, uc: Vector2, l1: float, l2: float, bukulme: float) -> Vector2:
	"""İki kemikli zincirde orta eklem (diz/dirsek). bukulme: +1/-1 hangi tarafa kıvrılacağı."""
	var fark: Vector2 = uc - kok
	var d: float = clampf(fark.length(), absf(l1 - l2) + 0.01, l1 + l2 - 0.01)
	var eksen: Vector2 = fark.normalized() if fark.length() > 0.001 else Vector2.DOWN
	var a: float = (l1 * l1 - l2 * l2 + d * d) / (2.0 * d)
	var h: float = sqrt(maxf(0.0, l1 * l1 - a * a))
	return kok + eksen * a + Vector2(-eksen.y, eksen.x) * h * bukulme

func _uzuv_ciz(kok: Vector2, uc: Vector2, l1: float, l2: float, bukulme: float, renk: Color) -> void:
	var fark: Vector2 = uc - kok
	if fark.length() > l1 + l2:
		uc = kok + fark.normalized() * (l1 + l2)
	var eklem: Vector2 = _eklem_bul(kok, uc, l1, l2, bukulme)
	draw_line(kok, eklem, renk, line_width)
	draw_line(eklem, uc, renk, line_width)
	draw_circle(eklem, line_width * 0.5, renk)

func _draw_walk(dir: float) -> void:
	var p: float = walk_phase
	var k: float = clampf(absf(velocity.x) / SPEED, 0.0, 1.2)  # Adım büyüklüğü hıza bağlı
	var arka_renk: Color = outline_color.darkened(0.25)
	
	# Gövde: ayaklar alttan geçerken yükselir, çift basışta alçalır; hız arttıkça öne eğilir
	var bob: float = (1.0 - absf(cos(p))) * 2.5 * k
	var kalca: Vector2 = Vector2(0.0, 6.0 - bob)
	var egilme: float = (3.0 + 2.0 * k) * k * dir
	var omuz: Vector2 = Vector2(egilme, -17.0 - bob)
	
	# Ayak yörüngesi: yerdeyken geriye kayar, öne giderken havalanır
	var adim: float = 11.0 * k
	var kaldirma: float = 8.0 * k
	var ayaklar: Array = []
	for faz in [p, p + PI]:
		var x: float = cos(faz) * adim * dir
		var y: float = 27.0 - maxf(0.0, -sin(faz)) * kaldirma
		ayaklar.append(Vector2(x, y))
	
	# Kollar bacakların tersine sallanır
	var kol_salinim: float = 8.0 * k + 1.0
	var eller: Array = []
	for faz in [p + PI, p]:
		eller.append(omuz + Vector2(cos(faz) * kol_salinim * dir + egilme * 0.3, 15.0 - absf(sin(faz)) * 2.0 * k))
	
	# Arkadaki uzuvlar önce (koyu), öndekiler sonra
	_uzuv_ciz(kalca, ayaklar[1], UYLUK, BALDIR, -dir, arka_renk)
	_uzuv_ciz(omuz, eller[1], PAZU, ONKOL, dir, arka_renk)
	draw_line(kalca, omuz, outline_color, line_width)
	_uzuv_ciz(kalca, ayaklar[0], UYLUK, BALDIR, -dir, outline_color)
	_uzuv_ciz(omuz, eller[0], PAZU, ONKOL, dir, outline_color)
	
	# Kafa ve yüz
	var kafa_merkez: Vector2 = omuz + Vector2(egilme * 0.4, -11.0)
	draw_circle(kafa_merkez, 12.0, outline_color)
	draw_circle(kafa_merkez, 10.0, body_color)
	draw_circle(kafa_merkez + Vector2(4.0 * dir, -2), 1.8, eye_color)
	
	var agiz_start: Vector2 = kafa_merkez + Vector2(1.0 * dir, 3)
	var agiz_end: Vector2 = agiz_start + Vector2(4.0 * dir, 0)
	draw_line(agiz_start, agiz_end, outline_color, 1.5)

func _draw_jump(dir: float) -> void:
	var kalca: Vector2 = Vector2(0, 5)
	var sol_diz: Vector2 = Vector2(-10, 12)
	var sol_ayak: Vector2 = Vector2(-6, 20)
	var sag_diz: Vector2 = Vector2(10, 12)
	var sag_ayak: Vector2 = Vector2(6, 20)
	
	draw_line(kalca, sol_diz, outline_color, line_width)
	draw_line(sol_diz, sol_ayak, outline_color, line_width)
	draw_line(kalca, sag_diz, outline_color, line_width)
	draw_line(sag_diz, sag_ayak, outline_color, line_width)
	
	var omuz: Vector2 = Vector2(0, -20)
	draw_line(kalca, omuz, outline_color, line_width)
	
	var sol_omuz: Vector2 = omuz + Vector2(-3, 2)
	var sol_dirsek: Vector2 = sol_omuz + Vector2(-10, -8)
	var sol_el: Vector2 = sol_dirsek + Vector2(-4, -8)
	draw_line(sol_omuz, sol_dirsek, outline_color, line_width)
	draw_line(sol_dirsek, sol_el, outline_color, line_width)
	
	var sag_omuz: Vector2 = omuz + Vector2(3, 2)
	var sag_dirsek: Vector2 = sag_omuz + Vector2(10, -8)
	var sag_el: Vector2 = sag_dirsek + Vector2(4, -8)
	draw_line(sag_omuz, sag_dirsek, outline_color, line_width)
	draw_line(sag_dirsek, sag_el, outline_color, line_width)
	
	var kafa_merkez: Vector2 = Vector2(0, -30)
	draw_circle(kafa_merkez, 12.0, outline_color)
	draw_circle(kafa_merkez, 10.0, body_color)
	draw_circle(kafa_merkez + Vector2(3.0 * dir, -3), 2.0, eye_color)
	
	draw_circle(kafa_merkez + Vector2(2.0 * dir, 4), 2.5, outline_color)
	draw_circle(kafa_merkez + Vector2(2.0 * dir, 4), 1.5, body_color)

func _draw_fall(dir: float) -> void:
	var flutter: float = sin(anim_time * 15.0) * 3.0 
	
	var kalca: Vector2 = Vector2(0, 5)
	var sol_diz: Vector2 = Vector2(-12 + flutter, 14)
	var sol_ayak: Vector2 = Vector2(-15 + flutter * 1.5, 24)
	var sag_diz: Vector2 = Vector2(12 - flutter, 14)
	var sag_ayak: Vector2 = Vector2(15 - flutter * 1.5, 24)
	
	draw_line(kalca, sol_diz, outline_color, line_width)
	draw_line(sol_diz, sol_ayak, outline_color, line_width)
	draw_line(kalca, sag_diz, outline_color, line_width)
	draw_line(sag_diz, sag_ayak, outline_color, line_width)
	
	var omuz: Vector2 = Vector2(0, -18)
	draw_line(kalca, omuz, outline_color, line_width)
	
	var sol_omuz: Vector2 = omuz + Vector2(-3, 2)
	var sol_dirsek: Vector2 = sol_omuz + Vector2(-12 + flutter, -10)
	var sol_el: Vector2 = sol_dirsek + Vector2(-6 + flutter * 0.5, -6)
	draw_line(sol_omuz, sol_dirsek, outline_color, line_width)
	draw_line(sol_dirsek, sol_el, outline_color, line_width)
	
	var sag_omuz: Vector2 = omuz + Vector2(3, 2)
	var sag_dirsek: Vector2 = sag_omuz + Vector2(12 - flutter, -10)
	var sag_el: Vector2 = sag_dirsek + Vector2(6 - flutter * 0.5, -6)
	draw_line(sag_omuz, sag_dirsek, outline_color, line_width)
	draw_line(sag_dirsek, sag_el, outline_color, line_width)
	
	var kafa_merkez: Vector2 = Vector2(flutter * 0.3, -28)
	draw_circle(kafa_merkez, 12.0, outline_color)
	draw_circle(kafa_merkez, 10.0, body_color)
	draw_circle(kafa_merkez + Vector2(3.0 * dir, -2), 2.5, eye_color)
	
	draw_circle(kafa_merkez + Vector2(2.0 * dir, 4), 3.0, outline_color)
	draw_circle(kafa_merkez + Vector2(2.0 * dir, 4), 1.5, Color.BLACK)


func _draw_climb(_dir: float) -> void:
	# İkonun önünde, sırtı bize dönük: eller sırayla yukarı uzanır, karşı bacak iter
	var c: float = climb_phase
	var salinim: float = sin(c) * 1.5
	var kalca: Vector2 = Vector2(salinim, 7.0)
	var omuz: Vector2 = Vector2(salinim * 0.5, -17.0)
	
	# Uzanan el yukarı çıkar, tutan el aşağı iner (gövde yükselirken)
	var sol_el: Vector2 = Vector2(-18.0, -31.0 + sin(c) * 6.0)
	var sag_el: Vector2 = Vector2(18.0, -31.0 - sin(c) * 6.0)
	var sol_omuz: Vector2 = omuz + Vector2(-6.0, 1.0)
	var sag_omuz: Vector2 = omuz + Vector2(6.0, 1.0)
	# Karşı bacak: sağ el yukarıdayken sol ayak yukarı çekilir
	var sol_ayak: Vector2 = Vector2(-8.0, 25.0 - maxf(0.0, -sin(c)) * 9.0)
	var sag_ayak: Vector2 = Vector2(8.0, 25.0 - maxf(0.0, sin(c)) * 9.0)
	
	_uzuv_ciz(kalca, sol_ayak, UYLUK, BALDIR, 1.0, outline_color)
	_uzuv_ciz(kalca, sag_ayak, UYLUK, BALDIR, -1.0, outline_color)
	draw_line(kalca, omuz, outline_color, line_width)
	draw_line(sol_omuz, sag_omuz, outline_color, line_width)
	_uzuv_ciz(sol_omuz, sol_el, PAZU, ONKOL, -1.0, outline_color)
	_uzuv_ciz(sag_omuz, sag_el, PAZU, ONKOL, 1.0, outline_color)
	
	# Kafa arkadan (yüz görünmez), kolların önünde
	var kafa_merkez: Vector2 = omuz + Vector2(salinim * 0.3, -11.0)
	draw_circle(kafa_merkez, 12.0, outline_color)
	draw_circle(kafa_merkez, 10.0, body_color)

func _draw_build(dir: float) -> void:
	var offset: float = sin(Time.get_ticks_msec() / 100.0) * 1.5
	
	var govde_alt: Vector2 = Vector2(0, 10)
	var govde_ust: Vector2 = Vector2(0, -15)
	var omuz: Vector2 = Vector2(0, -12)
	
	draw_line(govde_alt, govde_ust, outline_color, line_width)
	
	var sol_diz: Vector2 = Vector2(-8, 25)
	var sol_ayak: Vector2 = Vector2(-10, 35)
	var sag_diz: Vector2 = Vector2(8, 25)
	var sag_ayak: Vector2 = Vector2(10, 35)
	
	draw_line(govde_alt, sol_diz, outline_color, line_width)
	draw_line(sol_diz, sol_ayak, outline_color, line_width)
	draw_line(govde_alt, sag_diz, outline_color, line_width)
	draw_line(sag_diz, sag_ayak, outline_color, line_width)
	
	# Kollar yukarıda, havada blok tutuyor gibi!
	var sol_dirsek: Vector2 = Vector2(-15, -25 + offset)
	var sol_el: Vector2 = Vector2(-5, -40 + offset)
	var sag_dirsek: Vector2 = Vector2(15, -25 + offset)
	var sag_el: Vector2 = Vector2(5, -40 + offset)
	
	draw_line(omuz, sol_dirsek, outline_color, line_width)
	draw_line(sol_dirsek, sol_el, outline_color, line_width)
	draw_line(omuz, sag_dirsek, outline_color, line_width)
	draw_line(sag_dirsek, sag_el, outline_color, line_width)
	
	# Kafa yukarı bakıyor
	var kafa_merkez: Vector2 = Vector2(0, -28 + offset)
	draw_circle(kafa_merkez, 12.0, outline_color)
	draw_circle(kafa_merkez, 10.0, body_color)
	draw_circle(kafa_merkez + Vector2(0, -5), 2.0, eye_color)
	
	# Elinde tuttuğu küçük gri kırıktaş önizlemesi
	draw_rect(Rect2(-10, -50 + offset, 20, 20), Color(0.5, 0.5, 0.5))
	draw_rect(Rect2(-10, -50 + offset, 20, 20), Color(0.2, 0.2, 0.2), false, 1.0)

func _draw_grabbed(dir: float) -> void:
	# TUTULMUŞ: Kollar ve bacaklar sarkık, kafa yukarıda (mouse tarafından tutuluyor)
	var swing: float = sin(anim_time * 3.0) * 4.0  # Hafif sallanma
	var swing2: float = sin(anim_time * 2.5 + 1.0) * 3.0
	
	# KAFA (Üstte, tutulduğu nokta — korkmuş yüz)
	var kafa_merkez: Vector2 = Vector2(swing * 0.3, -30)
	draw_circle(kafa_merkez, 12.0, outline_color)
	draw_circle(kafa_merkez, 10.0, body_color)
	# Korkmuş gözler (büyük, yuvarlak)
	draw_circle(kafa_merkez + Vector2(-4, -2), 2.5, eye_color)
	draw_circle(kafa_merkez + Vector2(4, -2), 2.5, eye_color)
	# Açık ağız (şaşkın/korkmuş "O")
	draw_circle(kafa_merkez + Vector2(0, 4), 3.0, outline_color)
	draw_circle(kafa_merkez + Vector2(0, 4), 1.8, Color(0.3, 0.0, 0.0))
	
	# GÖVDE (Sarkık)
	var omuz: Vector2 = Vector2(swing * 0.4, -18)
	var kalca: Vector2 = Vector2(swing * 0.8, 10)
	draw_line(omuz, kalca, outline_color, line_width)
	
	# KOLLAR (Yukarıda, tutunmaya çalışıyor)
	var sol_omuz: Vector2 = omuz + Vector2(-3, 2)
	var sol_dirsek: Vector2 = sol_omuz + Vector2(-6 + swing2, -12)
	var sol_el: Vector2 = sol_dirsek + Vector2(-2 + swing, -8)
	draw_line(sol_omuz, sol_dirsek, outline_color, line_width)
	draw_line(sol_dirsek, sol_el, outline_color, line_width)
	
	var sag_omuz: Vector2 = omuz + Vector2(3, 2)
	var sag_dirsek: Vector2 = sag_omuz + Vector2(6 - swing2, -12)
	var sag_el: Vector2 = sag_dirsek + Vector2(2 - swing, -8)
	draw_line(sag_omuz, sag_dirsek, outline_color, line_width)
	draw_line(sag_dirsek, sag_el, outline_color, line_width)
	
	# BACAKLAR (Sarkık, sallanıyor)
	var sol_diz: Vector2 = kalca + Vector2(-6 + swing, 12)
	var sol_ayak: Vector2 = sol_diz + Vector2(-3 + swing2, 12)
	var sag_diz: Vector2 = kalca + Vector2(6 - swing, 12)
	var sag_ayak: Vector2 = sag_diz + Vector2(3 - swing2, 12)
	
	draw_line(kalca, sol_diz, outline_color, line_width)
	draw_line(sol_diz, sol_ayak, outline_color, line_width)
	draw_line(kalca, sag_diz, outline_color, line_width)
	draw_line(sag_diz, sag_ayak, outline_color, line_width)

func _draw_thrown(dir: float) -> void:
	# FIRLATILMIŞ: Kollar/bacaklar açık, panikli hava pozu
	var spin: float = anim_time * 8.0  # Hızlı dönme/sallanma
	var flutter: float = sin(spin) * 6.0
	var flutter2: float = cos(spin) * 5.0
	
	# KAFA (Panikli)
	var kafa_merkez: Vector2 = Vector2(flutter * 0.2, -28)
	draw_circle(kafa_merkez, 12.0, outline_color)
	draw_circle(kafa_merkez, 10.0, body_color)
	# Panikli gözler — "X" gözler
	var goz_sol = kafa_merkez + Vector2(-4, -2)
	var goz_sag = kafa_merkez + Vector2(4, -2)
	draw_line(goz_sol + Vector2(-2, -2), goz_sol + Vector2(2, 2), eye_color, 2.0)
	draw_line(goz_sol + Vector2(2, -2), goz_sol + Vector2(-2, 2), eye_color, 2.0)
	draw_line(goz_sag + Vector2(-2, -2), goz_sag + Vector2(2, 2), eye_color, 2.0)
	draw_line(goz_sag + Vector2(2, -2), goz_sag + Vector2(-2, 2), eye_color, 2.0)
	# Açık çığlık ağzı
	draw_circle(kafa_merkez + Vector2(0, 5), 3.5, outline_color)
	draw_circle(kafa_merkez + Vector2(0, 5), 2.0, Color(0.2, 0.0, 0.0))
	
	# GÖVDE
	var omuz: Vector2 = Vector2(flutter * 0.15, -18)
	var kalca: Vector2 = Vector2(flutter * 0.3, 5)
	draw_line(omuz, kalca, outline_color, line_width)
	
	# KOLLAR (Çılgınca açık, çırpınıyor)
	var sol_omuz: Vector2 = omuz + Vector2(-3, 2)
	var sol_dirsek: Vector2 = sol_omuz + Vector2(-14 + flutter, -8 + flutter2)
	var sol_el: Vector2 = sol_dirsek + Vector2(-8 + flutter2, -4 + flutter)
	draw_line(sol_omuz, sol_dirsek, outline_color, line_width)
	draw_line(sol_dirsek, sol_el, outline_color, line_width)
	
	var sag_omuz: Vector2 = omuz + Vector2(3, 2)
	var sag_dirsek: Vector2 = sag_omuz + Vector2(14 - flutter, -8 - flutter2)
	var sag_el: Vector2 = sag_dirsek + Vector2(8 - flutter2, -4 - flutter)
	draw_line(sag_omuz, sag_dirsek, outline_color, line_width)
	draw_line(sag_dirsek, sag_el, outline_color, line_width)
	
	# BACAKLAR (Açık ve çırpınıyor)
	var sol_diz: Vector2 = kalca + Vector2(-10 + flutter, 10 + flutter2 * 0.5)
	var sol_ayak: Vector2 = sol_diz + Vector2(-6 + flutter2, 10)
	var sag_diz: Vector2 = kalca + Vector2(10 - flutter, 10 - flutter2 * 0.5)
	var sag_ayak: Vector2 = sag_diz + Vector2(6 - flutter2, 10)
	
	draw_line(kalca, sol_diz, outline_color, line_width)
	draw_line(sol_diz, sol_ayak, outline_color, line_width)
	draw_line(kalca, sag_diz, outline_color, line_width)
	draw_line(sag_diz, sag_ayak, outline_color, line_width)

# ============================================================
# 4. AI (YAPAY ZEKA) KONTROL ARAYÜZÜ
# ============================================================
func ai_move_left() -> void:
	move_direction = -1

func ai_move_right() -> void:
	move_direction = 1

func ai_stop() -> void:
	move_direction = 0

func ai_jump() -> void:
	should_jump = true

func ai_move_to_target(target_x: float) -> void:
	var diff: float = target_x - global_position.x
	if abs(diff) < 15.0:
		ai_stop()
	elif diff > 0:
		ai_move_right()
	else:
		ai_move_left()

func _blok_sigar_mi(pos: Vector2) -> bool:
	"""İkonlar geçilebilir olduğu için sayılmaz; sadece başka blok ya da görev çubuğu engeller."""
	var space_state = get_world_2d().direct_space_state
	var query = PhysicsShapeQueryParameters2D.new()
	var rect = RectangleShape2D.new()
	rect.size = Vector2(38, 38) # 40x40 bloğun biraz içinden kontrol et ki sürtünmeleri hata saymasın
	query.shape = rect
	query.transform = Transform2D(0, pos)
	query.exclude = [self.get_rid()]
	
	for sonuc in space_state.intersect_shape(query):
		var cisim = sonuc["collider"]
		if cisim and not cisim.is_in_group("ikonlar"):
			return false
	return true

func get_status() -> Dictionary:
	return {
		"x": global_position.x,
		"y": global_position.y,
		"on_floor": is_on_floor(),
		"state": State.keys()[current_state],
		"velocity_x": velocity.x,
		"velocity_y": velocity.y,
		"facing_right": facing_right,
		"plan": plan.map(func(a): return a["tip"]),
		"hedef": hedef_isim
	}

# ============================================================
# 5. PLAN YÜRÜTÜCÜ v3
# ============================================================

func hedefe_git(isim: String) -> bool:
	"""Navigasyondan plan iste. Plan yoksa false döner."""
	plani_iptal()
	if nav == null or not is_on_floor():
		return false
	var yeni = nav.plan_yap(_ayak(), isim, true)
	if yeni.is_empty():
		return false
	hedef_isim = isim
	_yeniden_plan_sayisi = 0
	_plani_baslat(yeni)
	return true

func aylak_yuru(mesafe: float) -> bool:
	"""Üstünde durduğu yüzeyde hedefsizce biraz yürü."""
	plani_iptal()
	if nav == null:
		return false
	var s = nav.uzerindeki_yuzey(_ayak())
	if s.is_empty():
		return false
	var x = clampf(global_position.x + mesafe, s["x0"] + 20.0, s["x1"] - 20.0)
	if absf(x - global_position.x) < 60.0:
		return false
	hedef_isim = ""
	_plani_baslat([{"tip": "YURU", "a": s, "b": s, "kalkis_x": x, "varis_x": x}])
	return true

func plani_iptal() -> void:
	plan.clear()
	hedef_isim = ""
	move_direction = 0
	tirmaniyor = false
	duraksadi = false
	_gecis_y = INF
	set_collision_mask_value(IKON_KATMANI, true)

func _plani_baslat(yeni: Array) -> void:
	plan = yeni
	_asama = 0
	_adim_suresi = 0.0

func _ayak() -> Vector2:
	return Vector2(global_position.x, global_position.y + AYAK)

func _uzerinde_mi(s: Dictionary) -> bool:
	var ayak = _ayak()
	return is_on_floor() and absf(ayak.y - s["y"]) <= 8.0 \
			and ayak.x >= s["x0"] - 14.0 and ayak.x <= s["x1"] + 14.0

func _adim_bitti() -> void:
	plan.pop_front()
	_asama = 0
	_adim_suresi = 0.0
	tirmaniyor = false
	if plan.is_empty():
		move_direction = 0
		if hedef_isim != "":
			print("Hedefe ulaşıldı: ", hedef_isim)
		rota_tamamlandi.emit()

func _yeniden_planla(neden: String) -> void:
	print("Yeniden plan (", neden, ")")
	tirmaniyor = false
	move_direction = 0
	_yeniden_plan_sayisi += 1
	var yeni: Array = []
	if hedef_isim != "" and _yeniden_plan_sayisi <= MAX_YENIDEN_PLAN and nav:
		yeni = nav.plan_yap(_ayak(), hedef_isim, true)
	if yeni.is_empty():
		print("Vazgeçildi: ", hedef_isim)
		plan.clear()
		rota_tamamlandi.emit()
		return
	_plani_baslat(yeni)

func _git(x: float, tolerans: float) -> bool:
	"""x'e doğru yürü; vardıysa dur ve true döndür."""
	var fark = x - global_position.x
	# Fren mesafesini hesaba kat ki hedefi kayarak geçmesin
	var fren_mesafesi = velocity.x * velocity.x / (2.0 * ZEMIN_FREN) if fark * velocity.x > 0.0 else 0.0
	if absf(fark) <= tolerans + fren_mesafesi:
		move_direction = 0
		return true
	move_direction = 1 if fark > 0 else -1
	return false

func _adim_zaman_siniri(adim: Dictionary) -> float:
	var mesafe = absf(adim["kalkis_x"] - global_position.x)
	match adim["tip"]:
		"KULE":
			return 4.0 + mesafe / 150.0 + (global_position.y + AYAK - adim["hedef_ayak_y"]) / 40.0 * 1.5
		"KOPRU":
			return 4.0 + mesafe / 150.0 + absf(adim["b_yakin"] - adim["uc_x"]) / 40.0 * 1.5
		"TIRMAN":
			return 6.0 + mesafe / 150.0
		_:
			return 4.0 + absf(adim["varis_x"] - global_position.x) / 150.0

func _plan_yurut(delta: float) -> void:
	if plan.is_empty():
		return
	var adim: Dictionary = plan[0]
	if not adim.has("_sinir"):
		adim["_sinir"] = _adim_zaman_siniri(adim) + 1.0
	_adim_suresi += delta
	if _adim_suresi > adim["_sinir"] and is_on_floor():
		_yeniden_planla("zaman aşımı: " + adim["tip"])
		return
	
	if _dusunme > 0.0:
		_dusunme -= delta
		move_direction = 0
		return
	
	match adim["tip"]:
		"YURU":
			if is_on_floor() and _git(adim["varis_x"], 12.0):
				_adim_bitti()
			elif hava_suresi > 0.3:
				_asama = 9
			if _asama == 9 and is_on_floor():
				_inis_kontrol(adim)
		"ZIPLA":
			_yurut_zipla(adim)
		"TIRMAN":
			_yurut_tirman(adim)
		"DUS_IC":
			_yurut_dus_ic(adim)
		"DUS_KENAR":
			_yurut_dus_kenar(adim)
		"KULE":
			_yurut_kule(adim)
		"KOPRU":
			_yurut_kopru(adim)

func _inis_kontrol(adim: Dictionary) -> void:
	"""Havadan indik: doğru yere mi?"""
	if _uzerinde_mi(adim["b"]):
		_adim_bitti()
	else:
		_yeniden_planla("yanlış yere indim")

func _yurut_zipla(adim: Dictionary) -> void:
	match _asama:
		0:
			if not is_on_floor():
				return
			var yon = signf(adim["varis_x"] - adim["kalkis_x"])
			var gecti = yon != 0.0 and signf(global_position.x - adim["kalkis_x"]) == yon
			if _git(adim["kalkis_x"], 10.0) or gecti:
				if randf() < 0.3:
					_dusunme = randf_range(0.1, 0.35)
				_asama = 1
		1:
			if is_on_floor():
				move_direction = int(signf(adim["varis_x"] - global_position.x))
				ai_jump()
				_asama = 2
		2:
			_git(adim["varis_x"], 6.0)
			if not is_on_floor():
				_asama = 3
		3:
			_git(adim["varis_x"], 6.0)
			if is_on_floor():
				_inis_kontrol(adim)

func _yurut_tirman(adim: Dictionary) -> void:
	var b: Dictionary = adim["b"]
	match _asama:
		0:
			if is_on_floor() and _git(adim["kalkis_x"], 8.0):
				_asama = 1
		1:
			# Enerji dolana kadar dinlen, sonra kısa bir tereddüt
			move_direction = 0
			if is_on_floor() and climb_timer <= 0.05 and absf(velocity.x) < 20.0:
				_dusunme = randf_range(0.05, 0.3)
				_asama = 2
		2:
			ai_jump()
			tirmaniyor = true
			_asama = 3
		3:
			move_direction = 0
			if global_position.y + AYAK < b["y"] - 4.0:
				tirmaniyor = false
				_asama = 4
			elif not tirmaniyor and is_on_floor():
				_inis_kontrol(adim)
		4:
			_git(clampf(global_position.x, b["x0"] + 14.0, b["x1"] - 14.0), 4.0)
			if is_on_floor():
				_inis_kontrol(adim)

func _yurut_dus_ic(adim: Dictionary) -> void:
	match _asama:
		0:
			if is_on_floor() and _git(adim["kalkis_x"], 10.0):
				_asama = 1
		1:
			_gecis_y = adim["a"]["y"]
			_gecis_suresi = 0.6
			set_collision_mask_value(IKON_KATMANI, false)
			_asama = 2
		2:
			move_direction = 0
			if is_on_floor() and _gecis_y == INF:
				_inis_kontrol(adim)

func _yurut_dus_kenar(adim: Dictionary) -> void:
	match _asama:
		0:
			_git(adim["varis_x"], 4.0)
			if not is_on_floor() and hava_suresi > 0.05:
				_asama = 1
			elif is_on_floor() and absf(global_position.x - adim["varis_x"]) <= 4.0:
				_yeniden_planla("kenardan düşemedim")
		1:
			_git(adim["varis_x"], 10.0)
			if is_on_floor():
				_inis_kontrol(adim)

func _yurut_kule(adim: Dictionary) -> void:
	if _asama == 0:
		if is_on_floor() and _git(adim["kalkis_x"], 6.0):
			_asama = 1
		return
	
	move_direction = 0
	if _asama == 1:
		# Tamamen durunca kulenin x'ini bulunduğumuz yere sabitle (bloklar tam ayağımızın altına gelsin)
		if is_on_floor() and absf(velocity.x) < 2.0:
			adim["kule_x"] = global_position.x
			_asama = 2
		return
	var kule_x: float = adim["kule_x"]
	if is_on_floor() and global_position.y + AYAK <= adim["hedef_ayak_y"]:
		_adim_bitti()
		return
	
	if is_on_floor():
		_bu_ziplamada_koydum = false
		_kule_taban = global_position.y + AYAK
		if blok_bekleme <= 0.0:
			ai_jump()
	elif not _bu_ziplamada_koydum:
		# Ayak, yeni bloğun üst kenarını geçince altına koy (Minecraft nerd-pole).
		# Zıplama tepesi ~44px, blok 40px: yalnızca tepe noktasında birkaç karelik pencere var.
		var blok_ust = _kule_taban - 40.0
		if global_position.y + AYAK < blok_ust - 0.5:
			var blok_merkez = Vector2(kule_x, blok_ust + 20.0)
			if _blok_sigar_mi(blok_merkez):
				blok_koy.emit(blok_merkez)
				insaat_anim = 0.3
			_bu_ziplamada_koydum = true
			blok_bekleme = BLOK_BEKLEME_SURESI

func _yurut_kopru(adim: Dictionary) -> void:
	var yon: int = adim["yon"]
	var b_yakin: float = adim["b_yakin"]
	match _asama:
		0:
			_kopru_uc = adim["uc_x"]
			_asama = 1
		1:
			if not is_on_floor():
				if hava_suresi > 0.3:
					_asama = 9
				return
			# Köprü yeterince uzadı mı? Uzadıysa takip eylemine dönüş
			var kalan: float = (b_yakin - _kopru_uc) * yon
			var takip: String = adim["takip"]
			if (takip == "ZIPLA" and kalan <= adim["menzil"]) or (takip == "TIRMAN" and kalan <= -34.0) \
					or (takip == "HEDEF" and kalan <= -10.0):
				var b: Dictionary = adim["b"]
				var yeni: Dictionary
				if takip == "ZIPLA":
					var k = _kopru_uc - yon * 14.0
					yeni = {"tip": "ZIPLA", "a": adim["a"], "b": b, "kalkis_x": k, "varis_x": b_yakin + yon * 14.0}
				elif takip == "TIRMAN":
					var k = b_yakin + yon * 17.0
					yeni = {"tip": "TIRMAN", "a": adim["a"], "b": b, "kalkis_x": k, "varis_x": k}
				else:
					var k = _kopru_uc - yon * 20.0
					yeni = {"tip": "YURU", "a": adim["a"], "b": adim["a"], "kalkis_x": k, "varis_x": k}
				plan[0] = yeni
				_asama = 0
				_adim_suresi = 0.0
				return
			# Köprünün ucuna yürü, bir blok daha koy
			if _git(_kopru_uc - yon * 22.0, 6.0) and blok_bekleme <= 0.0:
				var blok_merkez = Vector2(_kopru_uc + yon * 20.0, adim["a"]["y"] + 20.0)
				if _blok_sigar_mi(blok_merkez):
					blok_koy.emit(blok_merkez)
					insaat_anim = 0.3
				elif not _blok_var_mi(blok_merkez):
					_yeniden_planla("köprü engellendi")
					return
				facing_right = yon > 0
				_kopru_uc += yon * 40.0
				blok_bekleme = BLOK_BEKLEME_SURESI
		9:
			if is_on_floor():
				_yeniden_planla("köprüden düştüm")

func _blok_var_mi(pos: Vector2) -> bool:
	for blok in get_tree().get_nodes_in_group("bloklar"):
		if blok.global_position.distance_to(pos) < 10.0:
			return true
	return false
