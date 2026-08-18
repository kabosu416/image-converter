from PIL import Image

def remove_pure_white_bg(input_path, output_path, tolerance=15):
    img = Image.open(input_path).convert("RGBA")
    
    # Get image data
    datas = img.getdata()
    
    newData = []
    # Find the background color from top-left pixel
    bg_color = datas[0]
    
    for item in datas:
        # Check if pixel is close to bg_color (or white)
        if (abs(item[0] - 255) < tolerance and 
            abs(item[1] - 255) < tolerance and 
            abs(item[2] - 255) < tolerance):
            # Transparent pixel
            newData.append((255, 255, 255, 0))
        else:
            newData.append(item)
            
    img.putdata(newData)
    img.save(output_path, "PNG")

remove_pure_white_bg('/Users/harukisakai/Downloads/1001000000818973564_4a05b09b280d7408be42aa513465ae96_1702194448009_1657782122097 2.JPG', 'static/img/logo.png', tolerance=20)
print("Saved simple transparent version")
