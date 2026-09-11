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

# --- ROTA TAKİP SİSTEMİ (A* Navigasyon) ---
var hedef_rota: Array = []       # Gidilecek waypoint listesi [Vector2, ...]
var hedefe_vardim: bool = true   # Rota tamamlandı mı?
signal rota_tamamlandi            # Hedefe ulaşınca sinyal gönder

# --- TIRMANMA MEKANİĞİ ---
const CLIMB_SPEED: float = 150.0   # Tırmanma hızı
const MAX_CLIMB_TIME: float = 0.8  # Kaç saniye aralıksız tırmanabilir
var climb_timer: float = 0.0       # Tırmanmaya harcanan süre

# --- İNŞAAT (BUILDER) MODU ---
var insaat_modu: bool = false
var insaat_hedefi: Vector2 = Vector2.ZERO
var insaat_asamasi: int = 0  # 0=zıplamaya hazır, 1=yükseliyor, 2=iniyor, 3=engelden kaçıyor
var insaat_kacis_yonu: int = 0 # 1=sağ, -1=sol
var blok_bekleme: float = 0.0  # Bloklar arası bekleme süresi
const BLOK_BEKLEME_SURESI: float = 0.8  # Her blok arasında 0.8 sn bekle
signal blok_koy(pozisyon: Vector2) # Sahne.gd'ye blok koyması için sinyal gönderir

# --- DURUM (STATE) MAKİNESİ ---
enum State { IDLE, WALK, JUMP, FALL, CLIMB, BUILD }
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

var tepe_sensoru: RayCast2D

# ============================================================
# 1. TEMEL DÖNGÜLER (FİZİK VE KONTROL)
# ============================================================

func _ready() -> void:
	# Kafayı çarpma durumlarını önceden tespit etmek için yukarı bakan sensör
	tepe_sensoru = RayCast2D.new()
	tepe_sensoru.target_position = Vector2(0, -120) # 120 piksel yukarıya bak
	tepe_sensoru.position = Vector2(0, -35) # Sensör kafadan başlasın
	add_child(tepe_sensoru)

func _process(delta: float) -> void:
	# Görsel animasyonların zamanlayıcılarını güncelliyoruz
	anim_time += delta
	breath_time += delta
	
	# Eğer klavye kontrolü açıksa, AI komutlarını klavye ile eziyoruz
	if OYUNCU_KONTROLU:
		_klavye_dinle()

func _physics_process(delta: float) -> void:
	# --- DİKEY HAREKET & TIRMANMA ---
	var tirmandimi = false
	
	# Blok bekleme süresini azalt
	if blok_bekleme > 0:
		blok_bekleme -= delta
	
	if is_on_floor():
		# Tırmanma enerjisi aniden dolmasın, 2 saniyede yavaşça dolsun (0.8 / 2 = 0.4 hızla azalır)
		if climb_timer > 0.0:
			climb_timer = max(0.0, climb_timer - delta * (MAX_CLIMB_TIME / 2.0))
		
		if should_jump:
			velocity.y = JUMP_VELOCITY
			should_jump = false
	else:
		# Havadayız. Duvara dayandık mı?
		if is_on_wall() and move_direction != 0:
			# Tırmanma enerjisi var mı?
			if climb_timer < MAX_CLIMB_TIME:
				velocity.y = -CLIMB_SPEED  # Yukarı tırman!
				climb_timer += delta
				tirmandimi = true
				current_state = State.CLIMB
			else:
				# ENERJİ BİTTİ! Düşmeden önce ayaklarının altına blok koy!
				if blok_bekleme <= 0:
					var blok_yeri = Vector2(global_position.x, global_position.y + 35 + 20)
					if _blok_sigar_mi(blok_yeri):
						blok_koy.emit(blok_yeri)
						blok_bekleme = BLOK_BEKLEME_SURESI
						# Eskiden enerjiyi anında sıfırlıyorduk, artık yavaşça dolacak.
						print("Tırmanma enerjisi bitti! Blok konuldu, dinleniyor...")
		
		# Tırmanmıyorsa normal yerçekimi uygula
		if not tirmandimi:
			velocity.y += gravity * GRAVITY_SCALE * delta
	
	should_jump = false # Güvenlik için zıplama tetikleyicisini sıfırla
	
	# --- YATAY HAREKET ---
	# Eğer oyuncu kontrolü kapalıysa rota takip sistemi çalışır
	if not OYUNCU_KONTROLU:
		rota_takip_et()
	
	velocity.x = move_direction * SPEED
	
	# --- YÜZÜNÜ DÖNME ---
	if move_direction != 0:
		facing_right = move_direction > 0
	
	# --- DURUM (STATE) GÜNCELLEMESİ ---
	_durumu_belirle()
	
	# Hareketi uygula
	move_and_slide()
	
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

func _durumu_belirle() -> void:
	if not is_on_floor():
		if velocity.y < 0:
			current_state = State.JUMP
		else:
			current_state = State.FALL
	elif move_direction != 0:
		current_state = State.WALK
	else:
		current_state = State.IDLE

# ============================================================
# 3. ÇÖP ADAM ÇİZİM MOTORU (PROCEDURAL ANIMATION)
# ============================================================

func _draw() -> void:
	var dir: float = 1.0 if facing_right else -1.0
	
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

func _draw_walk(dir: float) -> void:
	var cycle: float = anim_time * 7.0 
	var step: float = sin(cycle)
	var step2: float = sin(cycle + PI) 
	
	var bounce: float = abs(sin(cycle)) * 3.0
	var lean: float = sin(cycle) * 2.0 * dir 
	
	var kalca: Vector2 = Vector2(lean, 5 - bounce)
	
	# Sol Bacak
	var sol_kalca_aci: float = step * 0.5
	var sol_diz_x: float = -4 + sin(sol_kalca_aci + 0.3) * 12.0
	var sol_diz_y: float = 14 - bounce * 0.5 + abs(step) * 2.0
	var sol_diz: Vector2 = Vector2(sol_diz_x + lean, sol_diz_y)
	
	var sol_ayak_x: float = sol_diz_x * 0.8 + step * 6.0
	var sol_ayak_y: float = 27.0
	if step > 0.3:
		sol_ayak_y -= (step - 0.3) * 8.0
	var sol_ayak: Vector2 = Vector2(sol_ayak_x + lean, sol_ayak_y)
	
	# Sağ Bacak
	var sag_kalca_aci: float = step2 * 0.5
	var sag_diz_x: float = 4 + sin(sag_kalca_aci + 0.3) * 12.0
	var sag_diz_y: float = 14 - bounce * 0.5 + abs(step2) * 2.0
	var sag_diz: Vector2 = Vector2(sag_diz_x + lean, sag_diz_y)
	
	var sag_ayak_x: float = sag_diz_x * 0.8 + step2 * 6.0
	var sag_ayak_y: float = 27.0
	if step2 > 0.3:
		sag_ayak_y -= (step2 - 0.3) * 8.0
	var sag_ayak: Vector2 = Vector2(sag_ayak_x + lean, sag_ayak_y)
	
	draw_line(kalca, sol_diz, outline_color, line_width)
	draw_line(sol_diz, sol_ayak, outline_color, line_width)
	draw_line(kalca, sag_diz, outline_color, line_width)
	draw_line(sag_diz, sag_ayak, outline_color, line_width)
	
	# Gövde
	var omuz: Vector2 = Vector2(lean, -18 - bounce)
	draw_line(kalca, omuz, outline_color, line_width)
	
	# Kollar
	var kol_swing: float = sin(cycle) * 15.0
	
	var sol_omuz: Vector2 = omuz + Vector2(-3, 2)
	var sol_dirsek: Vector2 = sol_omuz + Vector2(-6 - kol_swing * 0.3, 10 + abs(kol_swing) * 0.2)
	var sol_el: Vector2 = sol_dirsek + Vector2(-kol_swing * 0.4, 8)
	draw_line(sol_omuz, sol_dirsek, outline_color, line_width)
	draw_line(sol_dirsek, sol_el, outline_color, line_width)
	
	var sag_omuz: Vector2 = omuz + Vector2(3, 2)
	var sag_dirsek: Vector2 = sag_omuz + Vector2(6 + kol_swing * 0.3, 10 + abs(kol_swing) * 0.2)
	var sag_el: Vector2 = sag_dirsek + Vector2(kol_swing * 0.4, 8)
	draw_line(sag_omuz, sag_dirsek, outline_color, line_width)
	draw_line(sag_dirsek, sag_el, outline_color, line_width)
	
	# Kafa ve Yüz
	var kafa_merkez: Vector2 = Vector2(lean * 1.2, -28 - bounce)
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


func _draw_climb(dir: float) -> void:
	var offset: float = sin(Time.get_ticks_msec() / 100.0) * 2.0  # Tırmanma titremesi
	
	var govde_alt: Vector2 = Vector2(5.0 * dir, 10 + offset)
	var govde_ust: Vector2 = Vector2(8.0 * dir, -15 + offset)
	var omuz: Vector2 = Vector2(7.0 * dir, -12 + offset)
	
	# Gövde
	draw_line(govde_alt, govde_ust, outline_color, line_width)
	
	# Bacaklar (Duvara yapışık ve ayrık)
	var sol_diz: Vector2 = Vector2(-2.0 * dir, 20 + offset)
	var sol_ayak: Vector2 = Vector2(5.0 * dir, 30 + offset)
	var sag_diz: Vector2 = Vector2(10.0 * dir, 18 - offset)
	var sag_ayak: Vector2 = Vector2(8.0 * dir, 28 - offset)
	
	draw_line(govde_alt, sol_diz, outline_color, line_width)
	draw_line(sol_diz, sol_ayak, outline_color, line_width)
	draw_line(govde_alt, sag_diz, outline_color, line_width)
	draw_line(sag_diz, sag_ayak, outline_color, line_width)
	
	# Kollar (Duvarı tutuyor)
	var sol_dirsek: Vector2 = Vector2(-2.0 * dir, -20 + offset)
	var sol_el: Vector2 = Vector2(10.0 * dir, -25 + offset)
	var sag_dirsek: Vector2 = Vector2(15.0 * dir, -20 - offset)
	var sag_el: Vector2 = Vector2(12.0 * dir, -30 - offset)
	
	draw_line(omuz, sol_dirsek, outline_color, line_width)
	draw_line(sol_dirsek, sol_el, outline_color, line_width)
	draw_line(omuz, sag_dirsek, outline_color, line_width)
	draw_line(sag_dirsek, sag_el, outline_color, line_width)
	
	# Kafa (Duvara bakıyor)
	var kafa_merkez: Vector2 = Vector2(10.0 * dir, -25 + offset)
	draw_circle(kafa_merkez, 12.0, outline_color)
	draw_circle(kafa_merkez, 10.0, body_color)
	draw_circle(kafa_merkez + Vector2(4.0 * dir, -3), 2.0, eye_color)

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
	var space_state = get_world_2d().direct_space_state
	var query = PhysicsShapeQueryParameters2D.new()
	var rect = RectangleShape2D.new()
	rect.size = Vector2(38, 38) # 40x40 bloğun biraz içinden kontrol et ki sürtünmeleri hata saymasın
	query.shape = rect
	query.transform = Transform2D(0, pos)
	
	# Çöp adamın kendisini yoksay
	query.exclude = [self.get_rid()]
	
	var sonuc = space_state.intersect_shape(query)
	return sonuc.is_empty()

func get_status() -> Dictionary:
	return {
		"x": global_position.x,
		"y": global_position.y,
		"on_floor": is_on_floor(),
		"state": State.keys()[current_state],
		"velocity_x": velocity.x,
		"velocity_y": velocity.y,
		"facing_right": facing_right,
		"hedefe_vardim": hedefe_vardim
	}

# ============================================================
# 5. ROTA VE İNŞAAT SİSTEMİ v2
# ============================================================

# Sıkışma algılama
var _son_pozisyon: Vector2 = Vector2.ZERO
var _sikisma_sayaci: float = 0.0
const SIKISMA_SURESI: float = 2.0  # 2 sn hareket etmediyse sıkışmış

func rotayi_ayarla(yeni_rota: Array) -> void:
	insaat_modu = false
	hedef_rota = yeni_rota.duplicate()
	hedefe_vardim = false
	_sikisma_sayaci = 0.0
	_son_pozisyon = global_position
	print("Rota: ", hedef_rota.size(), " waypoint")

func insaat_baslat(hedef_isim: String, hedef_pozisyon: Vector2) -> void:
	print("İNŞAAT: ", hedef_isim, " hedefine kule dikiliyor!")
	insaat_modu = true
	hedefe_vardim = false
	hedef_rota.clear()
	insaat_hedefi = hedef_pozisyon
	insaat_asamasi = 0  # İlk aşamadan başla
	_sikisma_sayaci = 0.0
	_son_pozisyon = global_position

func rota_takip_et() -> void:
	var delta = get_physics_process_delta_time()
	
	# --- SIKIŞMA ALGILAMA ---
	if global_position.distance_to(_son_pozisyon) < 5.0:
		_sikisma_sayaci += delta
	else:
		_sikisma_sayaci = 0.0
		_son_pozisyon = global_position
	
	if _sikisma_sayaci > SIKISMA_SURESI:
		print("SIKIŞMA ALGILANDI! Waypoint atlanıyor...")
		_sikisma_sayaci = 0.0
		if insaat_modu:
			# İnşaat modunda sıkışırsa vazgeç
			insaat_modu = false
			hedefe_vardim = true
			ai_stop()
			rota_tamamlandi.emit()
			return
		elif not hedef_rota.is_empty():
			hedef_rota.pop_front()  # Bu waypoint'i atla
			if hedef_rota.is_empty():
				hedefe_vardim = true
				ai_stop()
				rota_tamamlandi.emit()
				return
	
	# --- İNŞAAT MODU ---
	if insaat_modu:
		_insaat_yap()
		return
	
	# --- NORMAL ROTA TAKİBİ ---
	if hedef_rota.is_empty():
		if not hedefe_vardim:
			hedefe_vardim = true
			ai_stop()
			rota_tamamlandi.emit()
		return
	
	var hedef = hedef_rota[0] as Vector2
	var dx = hedef.x - global_position.x
	var dy = hedef.y - global_position.y
	
	# Hedefe vardık mı?
	if abs(dx) < 30.0 and abs(dy) < 60.0:
		hedef_rota.pop_front()
		if hedef_rota.is_empty():
			ai_stop()
			hedefe_vardim = true
			rota_tamamlandi.emit()
		return
	
	# ===== YÜKSEKLİK KONTROLÜ =====
	# Bu waypoint zıplayarak ulaşılamayacak kadar yüksekte mi?
	# max zıplama ~183px, güvenli sınır ~150px
	if dy < -150.0 and abs(dx) < 80.0 and is_on_floor():
		# Zıplayarak yetişemeyiz → İNŞAAT MODUNA GEÇ!
		print("Waypoint çok yüksek! İnşaat moduna geçiliyor...")
		insaat_hedefi = hedef
		insaat_modu = true
		insaat_asamasi = 0
		hedef_rota.pop_front()  # Bu waypoint'i rotadan çıkar (inşaat halledecek)
		return
	
	# Yatay hareket — hedefe doğru yürü
	ai_move_to_target(hedef.x)
	
	# Zıplama kararı
	if is_on_floor():
		if dy < -30.0 and abs(dx) < 100.0:
			ai_jump()
		elif is_on_wall() and abs(dx) > 10.0:
			ai_jump()


func _insaat_yap() -> void:
	var dx = insaat_hedefi.x - global_position.x
	var dy = insaat_hedefi.y - global_position.y
	
	# === AŞAMA 3: Engelden Kaçış ===
	if insaat_asamasi == 3:
		tepe_sensoru.force_raycast_update()
		# Eğer tepemiz boşaldıysa ve yere bastıysak kaçış biter
		if not tepe_sensoru.is_colliding() and is_on_floor():
			ai_stop()
			insaat_asamasi = 0
			insaat_hedefi.x = global_position.x # Geri dönmeye çalışmaması için X'i güncelle
			print("İnşaat: Açık alan bulundu, kuleye devam!")
		else:
			# Hala tepemiz doluysa veya havadaysak, kaçış yönüne yürümeye devam et
			# Eğer duvara çarptıysak yön değiştir
			if is_on_wall():
				insaat_kacis_yonu *= -1
			move_direction = insaat_kacis_yonu # ai_move_direction yok, değişkeni direkt ayarlıyoruz
		return

	# ADIM 1: Hedefin X konumuna yürü (Sadece aşama 0'dayken ve kaçmıyorken)
	if abs(dx) > 30.0 and insaat_asamasi == 0:
		ai_move_to_target(insaat_hedefi.x)
		return
	
	ai_stop()
	
	# Yeterince yükseldik mi? (hedef seviyesindeysek bitir)
	if dy >= -50.0:
		insaat_modu = false
		hedefe_vardim = true
		ai_stop()
		rota_tamamlandi.emit()
		print("İNŞAAT TAMAMLANDI!")
		return
	
	# NERD-POLING DÖNGÜSÜ (Minecraft tarzı)
	match insaat_asamasi:
		0:  # === AŞAMA 0: Zıplamaya hazır (yerdeyiz) ===
			if is_on_floor():
				tepe_sensoru.force_raycast_update()
				if tepe_sensoru.is_colliding():
					print("İnşaat: Tepemde engel var! Yana kayıyorum...")
					insaat_asamasi = 3 # Kaçış aşaması
					insaat_kacis_yonu = 1 if randf() > 0.5 else -1
				else:
					current_state = State.BUILD
					ai_jump()
					insaat_asamasi = 1
					print("İnşaat: Zıplıyorum!")
		
		1:  # === AŞAMA 1: Yükseliyoruz, tepe noktasını bekle ===
			# Kafamızı çarptıysak hemen kaçışa geç
			if is_on_ceiling():
				print("İnşaat: Kafamı çarptım! Kaçış moduna geçiliyor.")
				insaat_asamasi = 3
				insaat_kacis_yonu = 1 if randf() > 0.5 else -1
				return
				
			# Sürekli olarak tam ayaklarımızın altını (hedef X'te) kontrol et
			var ayak_y = global_position.y + 35
			var blok_merkez = Vector2(insaat_hedefi.x, ayak_y + 20)
			
			# Havadayken (velocity.y > -150) kontrol etmeye başla, sığdığı an koy!
			if velocity.y > -150.0:
				if _blok_sigar_mi(blok_merkez):
					blok_koy.emit(blok_merkez)
					insaat_asamasi = 2
					print("İnşaat: Blok tam sığdı ve koyuldu! y=", snapped(blok_merkez.y, 1))
				elif velocity.y >= 0.0 and is_on_floor():
					# Zıpladık, düşüşe geçtik ama blok koyacak boşluk bulamadık ve yere indik.
					# Demek ki sıkıştık veya yeterince zıplayamadık. Tekrar dene.
					insaat_asamasi = 0
		
		2:  # === AŞAMA 2: İniyoruz, bloğun üstüne inmeyi bekle ===
			if is_on_floor():
				insaat_asamasi = 0  # Yeni döngü başlat
				print("İnşaat: Bloğa indim! y=", snapped(global_position.y, 1))
