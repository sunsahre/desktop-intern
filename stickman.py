import sys
import random
from PyQt6.QtWidgets import QApplication, QWidget
from PyQt6.QtGui import QPainter, QPen, QColor
from PyQt6.QtCore import Qt, QTimer, QPoint

class StickmanPet(QWidget):
    def __init__(self):
        super().__init__()
        
        # Pencere ayarları: Çerçevesiz, her zaman üstte, saydam arka plan
        self.setWindowFlags(
            Qt.WindowType.FramelessWindowHint | 
            Qt.WindowType.WindowStaysOnTopHint | 
            Qt.WindowType.Tool
        )
        self.setAttribute(Qt.WidgetAttribute.WA_TranslucentBackground)
        
        # Boyutlar
        self.resize(100, 150)
        
        # Başlangıç konumu (ekranın ortası)
        screen = QApplication.primaryScreen().geometry()
        self.move(screen.width() // 2, screen.height() // 2)

        # Durum değişkenleri
        self.x_dir = random.choice([-1, 1])
        self.speed = 2
        
        # Hareket zamanlayıcısı (AI bağlanana kadar rastgele dolaşsın)
        self.timer = QTimer(self)
        self.timer.timeout.connect(self.update_position)
        self.timer.start(50)  # 50ms = ~20 FPS

    def update_position(self):
        # Şimdilik sağa sola git, ekran kenarına çarpınca dön
        current_pos = self.pos()
        screen = QApplication.primaryScreen().geometry()
        
        new_x = current_pos.x() + (self.speed * self.x_dir)
        new_y = current_pos.y()
        
        # Ekran sınırları kontrolü
        if new_x <= 0 or new_x + self.width() >= screen.width():
            self.x_dir *= -1  # Yön değiştir
            
        self.move(new_x, new_y)
        self.update() # Ekranı yeniden çiz

    def paintEvent(self, event):
        painter = QPainter(self)
        painter.setRenderHint(QPainter.RenderHint.Antialiasing)
        
        # Kalem ayarları
        pen = QPen(QColor(0, 0, 0)) # Siyah
        pen.setWidth(4)
        painter.setPen(pen)
        
        # Çöp adam çizimi
        # Kafa
        painter.drawEllipse(35, 20, 30, 30)
        # Gövde
        painter.drawLine(50, 50, 50, 100)
        # Kollar
        # Hareket yönüne göre kollar sallanabilir ama şimdilik sabit
        painter.drawLine(50, 60, 20, 80)  # Sol Kol
        painter.drawLine(50, 60, 80, 80)  # Sağ Kol
        # Bacaklar
        painter.drawLine(50, 100, 30, 140) # Sol Bacak
        painter.drawLine(50, 100, 70, 140) # Sağ Bacak

        painter.end()

if __name__ == '__main__':
    app = QApplication(sys.argv)
    stickman = StickmanPet()
    stickman.show()
    sys.exit(app.exec())
