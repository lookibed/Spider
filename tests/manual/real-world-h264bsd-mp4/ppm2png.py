import os
import subprocess
from pathlib import Path

def convert_ppm_to_png():
    # Получаем текущую директорию, где находится скрипт
    current_dir = Path("./generated/frames/")
    
    # Находим все .ppm файлы
    ppm_files = list(current_dir.glob("*.ppm")) + list(current_dir.glob("*.PPM"))
    
    if not ppm_files:
        print("Файлы .ppm не найдены в текущей папке.")
        return
    
    print(f"Найдено {len(ppm_files)} файлов .ppm")
    
    for ppm_path in ppm_files:
        # Создаем имя для выходного PNG файла
        png_path = ppm_path.with_suffix('.png')
        
        # Пропускаем, если файл уже существует (опционально)
        if png_path.exists():
            print(f"⚠ Пропуск: {png_path.name} уже существует")
            continue
        
        # Команда ffmpeg
        cmd = [
            'ffmpeg',
            '-y',  # Перезаписывать выходной файл
            '-i', str(ppm_path),
            str(png_path)
        ]
        
        print(f"🔄 Конвертация: {ppm_path.name} -> {png_path.name}")
        
        try:
            # Запускаем ffmpeg
            result = subprocess.run(cmd, capture_output=True, text=True, check=True)
            print(f"✅ Готово: {png_path.name}")
        except subprocess.CalledProcessError as e:
            print(f"❌ Ошибка при конвертации {ppm_path.name}:")
            print(e.stderr)
        except FileNotFoundError:
            print("❌ ffmpeg не найден. Убедитесь, что ffmpeg установлен и доступен в PATH.")
            break

if __name__ == "__main__":
    convert_ppm_to_png()