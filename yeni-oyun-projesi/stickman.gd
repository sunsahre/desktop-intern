extends CharacterBody2D

# ============================================================
# ÇÖP ADAM (STICKMAN) - FİZİK VE ANİMASYON SİSTEMİ
# ============================================================

# --- HAREKET VE FİZİK AYARLARI ---
@export var SPEED: float = 300.0
@export var JUMP_VELOCITY: float = -600.0
@export var GRAVITY_SCALE: float = 1.0
@export var OYUNCU_KONTROLU: bool = true # Klavye ile test etmek için Inspector'dan kapatıp açabilirsin

# --- AI VE KONTROL DEĞİŞKENLERİ ---
var move_direction: int = 0   # -1 = sol, 0 = dur, 1 = sağ
var should_jump: bool = false

# --- DURUM (STATE) MAKİNESİ ---
enum State { IDLE, WALK, JUMP, FALL }
var current_state: State = State.IDLE
var facing_right: bool = true

# --- ÇİZİM VE KOZMETİK AYARLAR ---
var body_color: Color = Color.WHITE
var outline_color: Color = Color.GREEN
var eye_color: Color = Color.BLACK
var line_width: float = 3.0

# Yerçekimini proje ayarlarından dinamik çekiyoruz
var gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")

# --- ZAMANLAYICILAR (Animasyonlar İçin) ---
var anim_time: float = 0.0
var breath_time: float = 0.0

# ============================================================
# 1. TEMEL DÖNGÜLER (FİZİK VE KONTROL)
# ============================================================

func _process(delta: float) -> void:
	# Görsel animasyonların zamanlayıcılarını güncelliyoruz
	anim_time += delta
	breath_time += delta
	
	# Eğer klavye kontrolü açıksa, AI komutlarını klavye ile eziyoruz
	if OYUNCU_KONTROLU:
		_klavye_dinle()

func _physics_process(delta: float) -> void:
	# --- YERÇEKİMİ UYGULAMASI ---
	if not is_on_floor():
		velocity.y += gravity * GRAVITY_SCALE * delta
	
	# --- ZIPLAMA KONTROLÜ ---
	if should_jump and is_on_floor():
		velocity.y = JUMP_VELOCITY
		should_jump = false # Zıpladıktan sonra tetikleyiciyi sıfırla
	
	# --- YATAY HAREKET ---
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
	
	# KAFA VE YÜZ
	var kafa_merkez: Vector2 = Vector2(0, -28 + nefes)
	draw_circle(kafa_merkez, 10.0, body_color)
	draw_arc(kafa_merkez, 10.0, 0, TAU, 32, outline_color, 2.0)
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
	draw_circle(kafa_merkez, 10.0, body_color)
	draw_arc(kafa_merkez, 10.0, 0, TAU, 32, outline_color, 2.0)
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
	draw_circle(kafa_merkez, 10.0, body_color)
	draw_arc(kafa_merkez, 10.0, 0, TAU, 32, outline_color, 2.0)
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
	draw_circle(kafa_merkez, 10.0, body_color)
	draw_arc(kafa_merkez, 10.0, 0, TAU, 32, outline_color, 2.0)
	draw_circle(kafa_merkez + Vector2(3.0 * dir, -2), 2.5, eye_color)
	
	draw_circle(kafa_merkez + Vector2(2.0 * dir, 4), 3.0, outline_color)
	draw_circle(kafa_merkez + Vector2(2.0 * dir, 4), 2.0, body_color)

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

func get_status() -> Dictionary:
	return {
		"x": global_position.x,
		"y": global_position.y,
		"on_floor": is_on_floor(),
		"state": State.keys()[current_state],
		"velocity_x": velocity.x,
		"velocity_y": velocity.y,
		"facing_right": facing_right
	}
