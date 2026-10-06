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
signal rota_tamamlandi(basarili: bool)  # Hedefe ulaşınca true, vazgeçince false
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
var outline_color: Color = Color(1.0, 0.43, 0.0)  # The Second Coming turuncusu
var line_width: float = 4.0  # Kalın çizgiler (AvM tarzı)
const BOYUT: float = 1.25
const CIZIM_TABANI: Vector2 = Vector2(0, 29.0)  # Çizimde ayak tabanı; büyütme bu noktaya göre

# Yerçekimini proje ayarlarından dinamik çekiyoruz
var gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")

# --- ZAMANLAYICILAR (Animasyonlar İçin) ---
var anim_time: float = 0.0
var breath_time: float = 0.0

# --- MOUSE İLE TUTMA / FIRLATMA ---
signal yakalandi
signal yere_indi                     # Fırlatıldıktan sonra yere inip kendine geldi
const TUTMA_NOKTASI: Vector2 = Vector2(0, -64)  # Kafanın tepesinden tutulur
const TUTMA_TAKIP: float = 30.0      # Fareye ne kadar sıkı yapışsın (büyük = daha sıkı)
const FIRLATMA_CARPANI: float = 1.2
const MAX_FIRLATMA_HIZI: float = 2200.0
var is_grabbed: bool = false         # Şu an tutulmuş mu?
var is_thrown: bool = false          # Ragdoll'da mı? (fırlatılma, yerde yatma, kalkma)
var fare_hizi: Vector2 = Vector2.ZERO
var _onceki_fare: Vector2 = Vector2.ZERO

# --- RAGDOLL (tutulma / fırlatılma) ---
# Nokta sırası: kafa, omuz, kalça, arka dirsek, arka el, ön dirsek, ön el, arka diz, arka ayak, ön diz, ön ayak
enum { R_KAFA, R_OMUZ, R_KALCA, R_DIRSEK_A, R_EL_A, R_DIRSEK_B, R_EL_B, R_DIZ_A, R_AYAK_A, R_DIZ_B, R_AYAK_B }
const R_SEKME: float = 0.25          # Çarpınca normal hızın ne kadarı geri seker
const R_SURTUNME: float = 0.15       # Yere sürtünürken kare başı teğet hız kaybı
const R_STATIK_SURTUNME: float = 0.8 # Bundan yavaş kayan temas noktası (px/kare) durur
const R_SEKME_ESIGI: float = 4.0     # Bundan yavaş (px/kare) çarpmalar sekmez, yerde titremesin
const R_HAVA_SONUMU: float = 0.995
const R_ITERASYON: int = 8
const YERDE_MIN: float = 1.2         # Durduktan sonra en az bu kadar yatar
const YERDE_MAX: float = 3.5
const KALKIS_DIZ: float = 0.6        # Yerden dizine doğrulma süresi
const KALKIS_AYAK: float = 0.5       # Dizden ayağa kalkma süresi
var r_nokta: PackedVector2Array = PackedVector2Array()
var r_onceki: PackedVector2Array = PackedVector2Array()
var r_temas: PackedByteArray = PackedByteArray()
var r_normal: PackedVector2Array = PackedVector2Array()
var _r_cubuklar: Array = []          # [a, b, uzunluk, min_mi]
var _r_sakin_sure: float = 0.0
var _r_ucus_sure: float = 0.0
var _r_max_darbe: float = 0.0
var _yerde_sure: float = 0.0
var _kalkis_sure: float = -1.0
var _kalkis_baslangic: PackedVector2Array = PackedVector2Array()

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
	
	var tirmandimi = false
	
	if blok_bekleme > 0:
		blok_bekleme -= delta
	if insaat_anim > 0:
		insaat_anim -= delta
	
	# --- KARAR (yürütücü move_direction / should_jump / tirmaniyor ayarlar) ---
	if not OYUNCU_KONTROLU:
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
		# Döngü hızı = yer hızı / adım boyu: basan ayak yere göre sabit kalır, kaymaz
		walk_phase += absf(velocity.x) / _adim_boyu(_hiz_orani()) * delta
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
	if not is_thrown:
		_ragdoll_kur()
	is_grabbed = true
	is_thrown = false
	_kalkis_sure = -1.0
	velocity = Vector2.ZERO
	move_direction = 0
	should_jump = false
	duraksadi = false
	current_state = State.GRABBED
	_onceki_fare = get_global_mouse_position()
	fare_hizi = Vector2.ZERO
	# Kafa ilk karede fareye ışınlanırsa gövde yukarı fırlar; bütün ragdoll'u kaydır
	var kayma: Vector2 = _tutma_pini(_onceki_fare) - r_nokta[R_KAFA]
	for i in r_nokta.size():
		r_nokta[i] += kayma
		r_onceki[i] += kayma
	global_position = _onceki_fare - TUTMA_NOKTASI
	plani_iptal()
	yakalandi.emit()

func _tutma_pini(fare: Vector2) -> Vector2:
	return fare + Vector2(0.0, (KAFA_RY + line_width * 0.5) * BOYUT)

func birak() -> void:
	"""Fare bırakılınca çağrılır — farenin son hızıyla fırlatır."""
	if not is_grabbed:
		return
	is_grabbed = false
	is_thrown = true
	current_state = State.THROWN
	_r_sakin_sure = 0.0
	_r_ucus_sure = 0.0
	_r_max_darbe = 0.0
	_yerde_sure = -1.0
	_kalkis_sure = -1.0
	# Kafa elin hızını tam alır, gövde ve uzuvlar geride kalır: fırlatınca kendi etrafında döner
	var dt: float = 1.0 / Engine.physics_ticks_per_second
	var atis: Vector2 = (fare_hizi * FIRLATMA_CARPANI).limit_length(MAX_FIRLATMA_HIZI) * dt
	for i in r_nokta.size():
		var pay: float = 1.0 if i == R_KAFA else 0.55
		var v: Vector2 = (r_nokta[i] - r_onceki[i]).lerp(atis, pay).limit_length(MAX_FIRLATMA_HIZI * dt)
		r_onceki[i] = r_nokta[i] - v

func firlatma_bitti_mi() -> bool:
	return not is_grabbed and not is_thrown

func _tutulma_fizigi(delta: float) -> void:
	var fare: Vector2 = get_global_mouse_position()
	var anlik_hiz: Vector2 = (fare - _onceki_fare) / delta
	_onceki_fare = fare
	fare_hizi = fare_hizi.lerp(anlik_hiz, 0.4)
	
	# Kafa fareye sabit; gövde ve uzuvlar ataletle geride kalıp sallanır
	global_position = fare - TUTMA_NOKTASI
	_ragdoll_adim(delta, true, _tutma_pini(fare))
	current_state = State.GRABBED

func _firlatma_fizigi(delta: float) -> void:
	current_state = State.THROWN
	if _kalkis_sure >= 0.0:
		_kalkis_yurut(delta)
		return
	
	_ragdoll_adim(delta, false, Vector2.ZERO)
	global_position = r_nokta[R_KALCA]
	_r_ucus_sure += delta
	
	if _yerde_sure < 0.0:
		var hareketsiz := true
		for i in r_nokta.size():
			if r_nokta[i].distance_to(r_onceki[i]) > 0.35:
				hareketsiz = false
				break
		var temas: int = 0
		for t in r_temas:
			temas += t
		_r_sakin_sure = _r_sakin_sure + delta if hareketsiz and temas >= 2 else 0.0
		if _r_sakin_sure > 0.35 or _r_ucus_sure > 8.0:
			# Sert düştükçe daha uzun yerde kalır
			_yerde_sure = clampf(YERDE_MIN + _r_max_darbe / 1000.0 * 1.2, YERDE_MIN, YERDE_MAX)
	else:
		_yerde_sure -= delta
		if _yerde_sure <= 0.0:
			_kalkisa_basla()

# --- RAGDOLL FİZİĞİ (Verlet noktaları + mesafe kısıtları + ışınla çarpışma) ---
func _tasarimdan_dunyaya(v: Vector2) -> Vector2:
	return global_position + v * BOYUT + CIZIM_TABANI * (1.0 - BOYUT)

func _ayakta_pozu(d: float) -> Array:
	return [Vector2(0, OMUZ_Y - BOYUN), Vector2(0.5 * d, OMUZ_Y), Vector2(0, KALCA_Y),
		Vector2(-5.5 * d, -13.5), Vector2(-8.0 * d, -3.0), Vector2(6.5 * d, -13.5), Vector2(8.5 * d, -3.0),
		Vector2(-4.0 * d, 10.5), Vector2(-6.0 * d, 27.0), Vector2(3.5 * d, 10.5), Vector2(5.0 * d, 27.0)]

func _diz_pozu(d: float) -> Array:
	# Arka diz yerde, ön ayak basmış, eller ön dizden destek alıyor
	return [Vector2(7.0 * d, -16.0), Vector2(3.0 * d, -4.0), Vector2(-1.0 * d, 12.0),
		Vector2(6.0 * d, 5.0), Vector2(11.0 * d, 12.0), Vector2(9.0 * d, 4.0), Vector2(13.0 * d, 13.0),
		Vector2(-3.0 * d, 27.0), Vector2(-19.0 * d, 27.0), Vector2(15.0 * d, 9.0), Vector2(15.0 * d, 27.0)]

func _ragdoll_kur() -> void:
	var dir: float = 1.0 if facing_right else -1.0
	r_nokta = PackedVector2Array()
	for v in _ayakta_pozu(dir):
		r_nokta.append(_tasarimdan_dunyaya(v))
	r_onceki = r_nokta.duplicate()
	r_temas = PackedByteArray()
	r_temas.resize(r_nokta.size())
	r_normal.resize(r_nokta.size())
	var s: float = BOYUT
	var govde: float = KALCA_Y - OMUZ_Y
	_r_cubuklar = [
		[R_KAFA, R_OMUZ, BOYUN * s, false],
		[R_OMUZ, R_KALCA, govde * s, false],
		[R_KAFA, R_KALCA, (BOYUN + govde) * s, false],  # Omurga bükülmez
		[R_OMUZ, R_DIRSEK_A, PAZU * s, false], [R_DIRSEK_A, R_EL_A, ONKOL * s, false],
		[R_OMUZ, R_DIRSEK_B, PAZU * s, false], [R_DIRSEK_B, R_EL_B, ONKOL * s, false],
		[R_KALCA, R_DIZ_A, UYLUK * s, false], [R_DIZ_A, R_AYAK_A, BALDIR * s, false],
		[R_KALCA, R_DIZ_B, UYLUK * s, false], [R_DIZ_B, R_AYAK_B, BALDIR * s, false],
		# Eklem sınırları: dirsek/diz tamamen katlanmaz, uyluk gövdeye yapışmaz, el kafaya girmez
		[R_OMUZ, R_EL_A, 13.0 * s, true], [R_OMUZ, R_EL_B, 13.0 * s, true],
		[R_KALCA, R_AYAK_A, 22.0 * s, true], [R_KALCA, R_AYAK_B, 22.0 * s, true],
		[R_OMUZ, R_DIZ_A, 18.0 * s, true], [R_OMUZ, R_DIZ_B, 18.0 * s, true],
		[R_KAFA, R_EL_A, 11.0 * s, true], [R_KAFA, R_EL_B, 11.0 * s, true],
	]

func _r_maske() -> int:
	# Tek yönlü ikon katmanı yerine onların katı kopyalarını gör
	return (collision_mask & ~(1 << (IKON_KATMANI - 1))) | (1 << (KiritasBlok.RAGDOLL_KATMANI - 1))

func _r_yaricap(i: int) -> float:
	if i == R_KAFA:
		return (KAFA_RY + line_width * 0.5) * BOYUT
	return line_width * 0.5 * BOYUT + 0.5

func _ragdoll_adim(delta: float, sabit: bool, sabit_nokta: Vector2) -> void:
	var g := Vector2(0.0, gravity * GRAVITY_SCALE * delta * delta)
	var baslangic: PackedVector2Array = r_nokta.duplicate()
	var on_hiz := PackedVector2Array()
	for i in r_nokta.size():
		var v: Vector2 = (r_nokta[i] - r_onceki[i]) * R_HAVA_SONUMU + g
		on_hiz.append(v)
		r_onceki[i] = r_nokta[i]
		r_nokta[i] += v
		r_temas[i] = 0
		r_normal[i] = Vector2.ZERO
	if sabit:
		r_nokta[R_KAFA] = sabit_nokta
	
	# Kısıtlar ve çarpışma aynı döngüde konum düzeltmesi olarak çözülür;
	# ayrı çözülünce yerde yatarken kısıt-çarpışma çekişmesi titreme yaratıyor
	for _k in R_ITERASYON:
		for c in _r_cubuklar:
			_cubuk_coz(c, sabit)
		if sabit:
			r_nokta[R_KAFA] = sabit_nokta
		for i in r_nokta.size():
			if not (sabit and i == R_KAFA):
				_carpisma_coz(i, baslangic[i])
	
	# Hız tepkisi bir kez: sert çarpmada hafif sekme, yerde kayarken sürtünme
	for i in r_nokta.size():
		if not r_temas[i]:
			continue
		var n: Vector2 = r_normal[i]
		var v: Vector2 = r_nokta[i] - r_onceki[i]
		var vn: float = v.dot(n)
		var vt: Vector2 = (v - n * vn) * (1.0 - R_SURTUNME)
		var carpma: float = on_hiz[i].dot(n)
		if carpma < 0.0:
			_r_max_darbe = maxf(_r_max_darbe, -carpma / delta)
			if carpma < -R_SEKME_ESIGI:
				vn = maxf(vn, -carpma * R_SEKME)
		r_onceki[i] = r_nokta[i] - (vt + n * vn)

func _cubuk_coz(c: Array, kafa_sabit: bool) -> void:
	var a: int = c[0]
	var b: int = c[1]
	var fark: Vector2 = r_nokta[b] - r_nokta[a]
	var d: float = fark.length()
	if d < 0.0001 or (c[3] and d >= c[2]):
		return
	# Gövde noktaları uzuvlardan ağır: savrulurken kollar/bacaklar gövdeyi peşinden sürükler
	var wa: float = _r_hafiflik(a, kafa_sabit)
	var wb: float = _r_hafiflik(b, kafa_sabit)
	if wa + wb <= 0.0:
		return
	var duzeltme: Vector2 = fark * ((d - c[2]) / d / (wa + wb))
	r_nokta[a] += duzeltme * wa
	r_nokta[b] -= duzeltme * wb

func _r_hafiflik(i: int, kafa_sabit: bool) -> float:
	if i == R_KAFA:
		return 0.0 if kafa_sabit else 0.8
	if i == R_OMUZ or i == R_KALCA:
		return 0.5
	return 1.0

func _carpisma_coz(i: int, baslangic: Vector2) -> void:
	var r: float = _r_yaricap(i)
	var hedef: Vector2 = r_nokta[i]
	var hareket: Vector2 = hedef - baslangic
	var uzay := get_world_2d().direct_space_state
	
	# Önce hareket yönünde, bulunamazsa aşağı doğru (zemine yaslanma) yarıçap kadar ileri bak
	var yon: Vector2 = hareket.normalized() if hareket.length() > 0.001 else Vector2.DOWN
	for uc in [hedef + yon * (r + 0.5), hedef + Vector2(0.0, r + 0.5)]:
		var sonuc: Dictionary = uzay.intersect_ray(PhysicsRayQueryParameters2D.create(baslangic, uc, _r_maske(), [get_rid()]))
		if not sonuc.is_empty() and _r_kabul(sonuc, hareket):
			var n: Vector2 = sonuc["normal"]
			var p: Vector2 = hedef
			# Yüzeyin içinden dışarı it
			var derinlik: float = (sonuc["position"] + n * r - p).dot(n)
			if derinlik > 0.0:
				p += n * derinlik
			# Statik sürtünme: yavaş kayan temas noktası olduğu yere yapışır
			var kayma: Vector2 = (p - baslangic) - n * (p - baslangic).dot(n)
			if kayma.length() < R_STATIK_SURTUNME:
				p -= kayma
			r_nokta[i] = p
			r_temas[i] = 1
			r_normal[i] = n
			break
	
	var ekran: Vector2 = get_viewport_rect().size
	var q: Vector2 = r_nokta[i]
	var n_ekran := Vector2.ZERO
	if q.x < r:
		q.x = r
		n_ekran = Vector2.RIGHT
	elif q.x > ekran.x - r:
		q.x = ekran.x - r
		n_ekran = Vector2.LEFT
	if q.y < r:
		q.y = r
		n_ekran = Vector2.DOWN
	elif q.y > ekran.y - r:
		q.y = ekran.y - r
		n_ekran = Vector2.UP
	if n_ekran != Vector2.ZERO:
		r_nokta[i] = q
		r_temas[i] = 1
		r_normal[i] = n_ekran

func _r_kabul(_sonuc: Dictionary, _hareket: Vector2) -> bool:
	# Yürürken tek yönlü olan ikon ve bloklar savrulurken her yönden katıdır (yanlara da çarpar).
	# İçlerinde başlayan ışın o şekle çarpmaz, yani ikonun önünde tutulan ragdoll dışarı düşebilir.
	return true

func _kalkisa_basla() -> void:
	var kalca: Vector2 = r_nokta[R_KALCA]
	var sorgu := PhysicsRayQueryParameters2D.create(kalca + Vector2(0, -20), kalca + Vector2(0, 200), _r_maske(), [get_rid()])
	var sonuc: Dictionary = get_world_2d().direct_space_state.intersect_ray(sorgu)
	var zemin_y: float = sonuc["position"].y if not sonuc.is_empty() else kalca.y
	var ekran_x: float = get_viewport_rect().size.x
	facing_right = r_nokta[R_KAFA].x > kalca.x
	global_position = Vector2(clampf(kalca.x, 25.0, ekran_x - 25.0), zemin_y - AYAK)
	_kalkis_baslangic = r_nokta.duplicate()
	_kalkis_sure = 0.0

func _kalkis_yurut(delta: float) -> void:
	# Yattığı pozdan önce dizine, sonra ayağa doğrulur
	_kalkis_sure += delta
	var dir: float = 1.0 if facing_right else -1.0
	var diz: Array = _diz_pozu(dir)
	var ayakta: Array = _ayakta_pozu(dir)
	for i in r_nokta.size():
		var diz_p: Vector2 = _tasarimdan_dunyaya(diz[i])
		if _kalkis_sure < KALKIS_DIZ:
			r_nokta[i] = _kalkis_baslangic[i].lerp(diz_p, smoothstep(0.0, KALKIS_DIZ, _kalkis_sure))
		else:
			var t: float = smoothstep(KALKIS_DIZ, KALKIS_DIZ + KALKIS_AYAK, _kalkis_sure)
			r_nokta[i] = diz_p.lerp(_tasarimdan_dunyaya(ayakta[i]), t)
	r_onceki = r_nokta.duplicate()
	if _kalkis_sure >= KALKIS_DIZ + KALKIS_AYAK:
		is_thrown = false
		_kalkis_sure = -1.0
		velocity = Vector2.ZERO
		current_state = State.IDLE
		yere_indi.emit()

# ============================================================
# 3. ÇÖP ADAM ÇİZİM MOTORU (PROCEDURAL ANIMATION)
# ============================================================

func _draw() -> void:
	var dir: float = 1.0 if facing_right else -1.0
	
	if is_grabbed or is_thrown:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(BOYUT, BOYUT))
		_draw_ragdoll()
		return
	
	# Pozlar küçük ölçekte tasarlandı; ayak tabanı sabit kalacak şekilde büyütülür
	draw_set_transform_matrix(Transform2D(0.0, Vector2(BOYUT, BOYUT), 0.0, CIZIM_TABANI * (1.0 - BOYUT)))
	
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

func _draw_idle(dir: float) -> void:
	var nefes: float = sin(breath_time * 2.0) * 1.0
	var kol_sallanma: float = sin(breath_time * 1.5) * 1.5
	var kalca := Vector2(0.0, KALCA_Y + nefes * 0.3)
	var omuz := Vector2(0.5 * dir, OMUZ_Y + nefes)
	
	# Ağırlık arka bacakta, ön diz hafif bükük (rahat duruş)
	_uzuv_ciz(kalca, Vector2(-6.0 * dir, 27.0), UYLUK, BALDIR, -dir, outline_color)
	_uzuv_ciz(kalca, Vector2(5.0 * dir, 27.0), UYLUK, BALDIR, -dir, outline_color)
	_cizgi(kalca, omuz, outline_color)
	# Kollar gövdenin iki yanında sarkar, dirsekler hafif dışa
	_uzuv_ciz(omuz, omuz + Vector2(-8.0 + kol_sallanma * 0.3, 19.0), PAZU, ONKOL, 1.0, outline_color)
	_uzuv_ciz(omuz, omuz + Vector2(8.0 - kol_sallanma * 0.3, 19.0), PAZU, ONKOL, -1.0, outline_color)
	_kafa_ciz(omuz + Vector2(0.0, -BOYUN))

# --- ÇİZİM YARDIMCILARI ---
# Oranlar: uzun bacaklar, kısa gövde, kafa doğrudan gövdeye oturur
const KAFA_RX: float = 9.5
const KAFA_RY: float = 10.5
const BOYUN: float = KAFA_RY + 2.0   # Kafa merkezinin omuzdan uzaklığı (halka gövdeye değer)
const KALCA_Y: float = -6.0
const OMUZ_Y: float = -22.0

func _cizgi(a: Vector2, b: Vector2, renk: Color) -> void:
	draw_line(a, b, renk, line_width)
	draw_circle(a, line_width * 0.5, renk)
	draw_circle(b, line_width * 0.5, renk)

func _kafa_ciz(merkez: Vector2, aci: float = 0.0, renk: Color = outline_color) -> void:
	# AvM tarzı içi boş, hafif oval halka kafa; yüz yok, ifade beden dilinden gelir
	var noktalar := PackedVector2Array()
	for i in 41:
		var t: float = TAU * i / 40.0
		noktalar.append(merkez + Vector2(cos(t) * KAFA_RX, sin(t) * KAFA_RY).rotated(aci))
	draw_polyline(noktalar, renk, line_width, true)

# --- IK YARDIMCILARI ---
const UYLUK: float = 17.0
const BALDIR: float = 17.0
const PAZU: float = 10.5
const ONKOL: float = 10.5

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
	draw_circle(kok, line_width * 0.5, renk)
	draw_circle(eklem, line_width * 0.5, renk)
	draw_circle(uc, line_width * 0.5, renk)

const KOSU_BASLA: float = 0.5   # Bu hız oranından itibaren yürüyüş koşuya karışmaya başlar
const KOSU_TAM: float = 0.8     # Bu hız oranında tamamen koşu

func _hiz_orani() -> float:
	return clampf(absf(velocity.x) / SPEED, 0.0, 1.2)

func _kosu_orani(k: float) -> float:
	return smoothstep(KOSU_BASLA, KOSU_TAM, k)

func _adim_boyu(k: float) -> float:
	return maxf(10.0, lerpf(15.0 * k, 21.0, _kosu_orani(k)))

func _yurume_pozu(p: float, k: float, dir: float) -> Dictionary:
	# Gövde: ayaklar alttan geçerken yükselir, çift basışta alçalır; hız arttıkça öne eğilir
	var bob: float = (1.0 - absf(cos(p))) * 3.0 * k
	var egilme: float = (2.5 + 2.0 * k) * k * dir
	var kalca := Vector2(0.0, KALCA_Y + 1.5 - bob)
	var poz := {"kalca": kalca, "omuz": kalca + Vector2(egilme, OMUZ_Y - KALCA_Y)}
	poz["kafa"] = poz["omuz"] + Vector2(egilme * 0.4, -BOYUN)
	
	# Ayak: yerdeyken geriye kayar, öne giderken havalanır
	var adim: float = _adim_boyu(k) if k > 0.05 else 0.0
	var ayaklar: Array = []
	for faz in [p, p + PI]:
		ayaklar.append(Vector2(cos(faz) * adim * dir, 27.0 - maxf(0.0, -sin(faz)) * 10.0 * k))
	poz["ayaklar"] = ayaklar
	
	# Kollar bacakların tersine, rahat sallanır
	var kol_salinim: float = 10.0 * k + 1.0
	var eller: Array = []
	for faz in [p + PI, p]:
		eller.append(poz["omuz"] + Vector2(cos(faz) * kol_salinim * dir + egilme * 0.3, 19.5 - absf(sin(faz)) * 2.5 * k))
	poz["eller"] = eller
	return poz

func _kosu_pozu(p: float, dir: float) -> Dictionary:
	# Alan Becker tarzı koşu: güçlü öne eğilme, iki ayağın havada olduğu uçuş anı,
	# yükselen ön diz, kalçaya savrulan arka topuk, 90° bükük pompalayan kollar
	var ucus: float = absf(cos(p)) * 5.0      # Bacaklar açıkken gövde en yüksekte
	var kalca := Vector2(0.0, KALCA_Y + 2.0 - ucus)
	var omuz := kalca + Vector2(8.0 * dir, -14.5)
	var poz := {"kalca": kalca, "omuz": omuz, "kafa": omuz + Vector2(4.5 * dir, -BOYUN + 0.5)}
	
	var adim: float = _adim_boyu(1.0)
	var ayaklar: Array = []
	for faz in [p, p + PI]:
		var ileri: float = cos(faz)                  # +1 önde, -1 arkada
		var havada: float = maxf(0.0, -sin(faz))     # Öne savrulma (salınım) fazı
		var kaldirma: float = havada * 17.0
		# Arka bacak salınıma başlarken topuk yukarı, kalçaya doğru savrulur
		kaldirma += havada * maxf(0.0, -ileri) * 12.0
		ayaklar.append(Vector2(ileri * adim * dir, 27.0 - kaldirma - ucus))
	poz["ayaklar"] = ayaklar
	
	# Kollar: pazu ileri-geri sallanır, ön kol ~100° bükük kalır ve öne bakar
	var eller: Array = []
	for faz in [p + PI, p]:
		var aci: float = cos(faz) * 1.2 - 0.2
		var pazu_yon := Vector2(sin(aci) * dir, cos(aci))
		var dirsek: Vector2 = omuz + pazu_yon * PAZU
		eller.append(dirsek + pazu_yon.rotated(-deg_to_rad(100.0) * dir) * ONKOL)
	poz["eller"] = eller
	return poz

func _draw_walk(dir: float) -> void:
	var p: float = walk_phase
	var k: float = _hiz_orani()
	var r: float = _kosu_orani(k)
	var arka_renk: Color = outline_color.darkened(0.25)
	
	var poz: Dictionary = _yurume_pozu(p, k, dir)
	if r > 0.0:
		var kosu: Dictionary = _kosu_pozu(p, dir)
		for anahtar in ["kalca", "omuz", "kafa"]:
			poz[anahtar] = poz[anahtar].lerp(kosu[anahtar], r)
		for liste in ["ayaklar", "eller"]:
			for i in 2:
				poz[liste][i] = poz[liste][i].lerp(kosu[liste][i], r)
	
	var kalca: Vector2 = poz["kalca"]
	var omuz: Vector2 = poz["omuz"]
	
	# Arkadaki uzuvlar önce (koyu), öndekiler sonra
	_uzuv_ciz(kalca, poz["ayaklar"][1], UYLUK, BALDIR, -dir, arka_renk)
	_uzuv_ciz(omuz, poz["eller"][1], PAZU, ONKOL, dir, arka_renk)
	_cizgi(kalca, omuz, outline_color)
	_uzuv_ciz(kalca, poz["ayaklar"][0], UYLUK, BALDIR, -dir, outline_color)
	
	_kafa_ciz(poz["kafa"], (omuz - kalca).angle() + PI / 2.0)
	
	# Öndeki kol koşarken yüz hizasına kadar kalktığı için kafanın önünde çizilir
	_uzuv_ciz(omuz, poz["eller"][0], PAZU, ONKOL, dir, outline_color)

func _draw_jump(_dir: float) -> void:
	# Toplanmış zıplama: dizler yukarı, kollar havada
	var kalca := Vector2(0.0, KALCA_Y)
	var omuz := Vector2(0.0, OMUZ_Y)
	_uzuv_ciz(kalca, kalca + Vector2(-7.0, 20.0), UYLUK, BALDIR, 1.0, outline_color)
	_uzuv_ciz(kalca, kalca + Vector2(7.0, 20.0), UYLUK, BALDIR, -1.0, outline_color)
	_cizgi(kalca, omuz, outline_color)
	_uzuv_ciz(omuz, omuz + Vector2(-15.0, -14.0), PAZU, ONKOL, -1.0, outline_color)
	_uzuv_ciz(omuz, omuz + Vector2(15.0, -14.0), PAZU, ONKOL, 1.0, outline_color)
	_kafa_ciz(omuz + Vector2(0.0, -BOYUN))

func _draw_fall(_dir: float) -> void:
	var flutter: float = sin(anim_time * 15.0) * 3.0
	var kalca := Vector2(0.0, KALCA_Y)
	var omuz := Vector2(0.0, OMUZ_Y)
	_uzuv_ciz(kalca, kalca + Vector2(-12.0 + flutter, 27.0), UYLUK, BALDIR, 1.0, outline_color)
	_uzuv_ciz(kalca, kalca + Vector2(12.0 - flutter, 27.0), UYLUK, BALDIR, -1.0, outline_color)
	_cizgi(kalca, omuz, outline_color)
	_uzuv_ciz(omuz, omuz + Vector2(-17.0 + flutter, -9.0), PAZU, ONKOL, -1.0, outline_color)
	_uzuv_ciz(omuz, omuz + Vector2(17.0 - flutter, -9.0), PAZU, ONKOL, 1.0, outline_color)
	_kafa_ciz(omuz + Vector2(flutter * 0.2, -BOYUN))

func _draw_climb(_dir: float) -> void:
	# İkonun önünde, sırtı bize dönük: eller sırayla yukarı uzanır, karşı bacak iter
	var c: float = climb_phase
	var salinim: float = sin(c) * 1.5
	var kalca := Vector2(salinim, KALCA_Y + 2.0)
	var omuz := Vector2(salinim * 0.5, OMUZ_Y + 1.0)
	
	# Uzanan el yukarı çıkar, tutan el aşağı iner (gövde yükselirken)
	var sol_el := Vector2(-17.0, OMUZ_Y - 14.0 + sin(c) * 6.0)
	var sag_el := Vector2(17.0, OMUZ_Y - 14.0 - sin(c) * 6.0)
	# Karşı bacak: sağ el yukarıdayken sol ayak yukarı çekilir
	var sol_ayak := Vector2(-8.0, 26.0 - maxf(0.0, -sin(c)) * 12.0)
	var sag_ayak := Vector2(8.0, 26.0 - maxf(0.0, sin(c)) * 12.0)
	
	_uzuv_ciz(kalca, sol_ayak, UYLUK, BALDIR, 1.0, outline_color)
	_uzuv_ciz(kalca, sag_ayak, UYLUK, BALDIR, -1.0, outline_color)
	_cizgi(kalca, omuz, outline_color)
	_uzuv_ciz(omuz, sol_el, PAZU, ONKOL, -1.0, outline_color)
	_uzuv_ciz(omuz, sag_el, PAZU, ONKOL, 1.0, outline_color)
	_kafa_ciz(omuz + Vector2(salinim * 0.3, -BOYUN))

func _draw_build(dir: float) -> void:
	# Hafif çömelmiş, bloğu iki eliyle öne-yukarı kaldırmış
	var offset: float = sin(Time.get_ticks_msec() / 100.0) * 1.5
	var kalca := Vector2(0.0, KALCA_Y + 3.0)
	var omuz := Vector2(1.0 * dir, OMUZ_Y + 3.0)
	_uzuv_ciz(kalca, Vector2(-9.0, 27.0), UYLUK, BALDIR, 1.0, outline_color)
	_uzuv_ciz(kalca, Vector2(9.0, 27.0), UYLUK, BALDIR, -1.0, outline_color)
	_cizgi(kalca, omuz, outline_color)
	_kafa_ciz(omuz + Vector2(0.0, -BOYUN))
	var el := Vector2(13.0 * dir, OMUZ_Y - 13.0 + offset)
	_uzuv_ciz(omuz, el + Vector2(-2.0 * dir, 0.0), PAZU, ONKOL, dir, outline_color.darkened(0.25))
	_uzuv_ciz(omuz, el + Vector2(2.0 * dir, 0.0), PAZU, ONKOL, dir, outline_color)
	
	# Elinde tuttuğu küçük gri kırıktaş önizlemesi
	var blok := Rect2(el.x - 10.0, el.y - 20.0, 20, 20)
	draw_rect(blok, Color(0.5, 0.5, 0.5))
	draw_rect(blok, Color(0.2, 0.2, 0.2), false, 1.0)

func _draw_ragdoll() -> void:
	var t := PackedVector2Array()
	for p in r_nokta:
		t.append((p - global_position) / BOYUT)
	var arka_renk: Color = outline_color.darkened(0.25)
	_cizgi(t[R_OMUZ], t[R_DIRSEK_A], arka_renk)
	_cizgi(t[R_DIRSEK_A], t[R_EL_A], arka_renk)
	_cizgi(t[R_KALCA], t[R_DIZ_A], arka_renk)
	_cizgi(t[R_DIZ_A], t[R_AYAK_A], arka_renk)
	_cizgi(t[R_OMUZ], t[R_KALCA], outline_color)
	_cizgi(t[R_KALCA], t[R_DIZ_B], outline_color)
	_cizgi(t[R_DIZ_B], t[R_AYAK_B], outline_color)
	_kafa_ciz(t[R_KAFA], (t[R_KAFA] - t[R_OMUZ]).angle() + PI / 2.0)
	_cizgi(t[R_OMUZ], t[R_DIRSEK_B], outline_color)
	_cizgi(t[R_DIRSEK_B], t[R_EL_B], outline_color)

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
	query.collision_mask = 0xFFFFFFFF & ~(1 << (KiritasBlok.RAGDOLL_KATMANI - 1))
	
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
		rota_tamamlandi.emit(true)

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
		rota_tamamlandi.emit(false)
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
