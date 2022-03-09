--[[-------------------------------------------------------------------------------
Aseprite script that provides some more functions for custom brushes:
	- Scaling
	- Flipping
	- Rotation in 90 degree increments/decrements
	- Select multiple brushes at once and either incrementally or randomly cycle
	  between them. 
	  
Note that the multiple brush selection must be done using the rectangular selection
tool, and the separate selections must be separated by at least one pixel otherwise
it won't work. 

By Thoof (@Thoof4 on twitter)
-------------------------------------------------------------------------------]]--

local brush_cap = 32

local sprite = app.activeSprite

local base_images = {} -- The base image of whatever brushes we're currently using 

local current_image_index = 0 -- The current brush image we're using

local fgcolor_changed = false
local bgcolor_changed = false 

local recolored_base_images = {} -- The recolored version of the base images, for if the user changes fgcolor/bgcolor

local resized_last_update = false
local last_image_scale_x = 100
local last_image_scale_y = 100

local rotation = 0 -- The rotation (Only goes in increments/decrements of 90 degrees)

local curr_offset = Point(0, 0)

local color_mode = app.activeSprite.colorMode

-- If we've got a custom brush currently then store it
if app.activeBrush.type == BrushType.IMAGE then
	base_images[0] = app.activeBrush.image

end

local function reset_brush_and_stop_events()

	reset_brush()
	app.events:off(on_fgcolorchange)
	app.events:off(on_bgcolorchange)
	if sprite ~= nil then
		sprite.events:off(on_sprite_change)
	end
end



-- Initialize the dialog --
local dlg = Dialog { title = "Custom Brush Options", onclose = reset_brush_and_stop_events }


local function convert_color_to_app_pixelcolor(color)
	return app.pixelColor.rgba(color.red, color.green, color.blue, color.alpha)
end 




local function get_pixel_alpha(pixel)
	local alpha = app.pixelColor.rgbaA(pixel)
	if app.activeSprite.colorMode == ColorMode.INDEXED then
		if pixel == app.activeSprite.spec.transparentColor then 
			alpha = 0
		else 
			alpha = 255
		end
	elseif app.activeSprite.colorMode == ColorMode.GRAY then 
		alpha = app.pixelColor.grayaA(pixel)
	end
	
	return alpha
end 

local function get_pixel_alpha_for_colormode(pixel, colormode)
	local alpha = app.pixelColor.rgbaA(pixel)
	if colormode == ColorMode.INDEXED then
		if pixel == app.activeSprite.spec.transparentColor then 
			alpha = 0
		else 
			alpha = 255
		end
	elseif colormode == ColorMode.GRAY then 
		alpha = app.pixelColor.grayaA(pixel)
	end
	
	return alpha
end 

local function get_pxc_as_color(pxc)
	return Color(app.pixelColor.rgbaR(pxc), app.pixelColor.rgbaG(pxc), app.pixelColor.rgbaB(pxc), get_pixel_alpha(pxc))
end

local function get_image_alpha_array(image)
	local a = {}
	local count = 0
	
	for it in image:pixels() do
		local pixelValue = it()
		
		local alpha = get_pixel_alpha(pixelValue)
		
		a[count] = alpha
		
	end 
	
	return a
end

-- Compares the alphas of two images and returns true if they're the same --
local function image_alpha_comparison(image1, image2)
	if (image1 == nil or image2 == nil) then
		return false
	end
	
	if (image1.width ~= image2.width) or (image1.height ~= image2.height) then
		return false
	end
	

	-- Wasn't sure how to use the api iterator to compare two images so this is not efficient
	local alpha_array_1 = get_image_alpha_array(image1)
	local alpha_array_2 = get_image_alpha_array(image2)
	
	for i = 1, #alpha_array_1 do
		if alpha_array_1[i] ~= alpha_array_2[i] then
			return false
		end
	end
	
	return true

end 

local function does_image_have_transparency(image)
	for it in image:pixels() do
		local pixelValue = it()
		
		local alpha = get_pixel_alpha(pixelValue)
		
		
		if alpha < 255 then
			return true
		end 
	end 
	return false
end 

-- Flips image and returns a copy -- 
local function get_flipped_image(image, flipX, flipY)
	local image_copy = Image(image.width, image.height, image.colorMode)
	
	for it in image:pixels() do
		local pixelValue = it()
		local x = it.x
		local y = it.y
		if flipX then
			x = image.width - it.x
		end
		if flipY then 
			y = image.height - it.y
		end
		
		image_copy:drawPixel(x, y, pixelValue)
	end 
	
	return image_copy
	
	
end

-- Note that this is only for rotation of increments of 90 degrees up to 270, positive and negative --
local function get_point_after_rotation(rotation, currX, currY, currWidth, currHeight)
	if (rotation == 90 or rotation == -270) then
		return Point(currY, currWidth - currX)
	elseif (rotation == -90 or rotation == 270) then
		return Point(currHeight - currY, currX)
	elseif (rotation == 180 or rotation == -180) then
		return Point(currWidth - currX, currHeight - currY)
	end
		
	return Point(0, 0)

end

-- Rotates the image, based on a rotation that must be some increment of 90 degrees (up to 270) --
local function rotate_image(image, rotation)
	local image_new = Image(image.height, image.width, image.colorMode)
	
	for it in image:pixels() do
		local pixelValue = it()
		local x = it.x
		local y = it.y
		
		local point_after_rot = get_point_after_rotation(rotation, x, y, image.width, image.height)
		
		image_new:drawPixel(point_after_rot.x, point_after_rot.y, pixelValue)
	end 
	
	return image_new
end

local function get_color_difference(color1, color2)
	local r = app.pixelColor.rgbaR(color1)
	local g = app.pixelColor.rgbaG(color1)
	local b = app.pixelColor.rgbaB(color1)
	local alpha = get_pixel_alpha(color1)
	
	local r2 = app.pixelColor.rgbaR(color2)
	local g2 = app.pixelColor.rgbaG(color2)
	local b2 = app.pixelColor.rgbaB(color2)
	local alpha2 = get_pixel_alpha(color2)
	
	local val = math.sqrt((r - r2)^2 + (g - g2)^2 + (b - b2)^2)
	return val
end 

local function get_closest_color_in_palette(app_pixel_color)
	local palette = app.activeSprite.palettes[1]

	local min_value = math.huge
	local index = 0
	for i = 0, #palette - 1 do
		local palette_color = convert_color_to_app_pixelcolor(palette:getColor(i))
	
		local diff = get_color_difference(app_pixel_color, palette_color)

		if diff < min_value then
			min_value = diff
			index = i
		end
	
	end
	
	return index
end

-- Colors a whole image with the specified color, without changing any alpha values --
local function color_whole_image_rgb(image, app_pixel_color)

	for it in image:pixels() do
		local pixelValue = it()
		
		local alpha = get_pixel_alpha(pixelValue)
		
		if alpha ~= 0 then
			it(app_pixel_color) -- Set pixel
		end
		
	end
	
end 



--[[  Applies the current foreground color to the image, in the same/a similar way to how brush colors change
	Rules for color change (These are only via my observations so may be somewhat inaccurate):
 		- If you have an image with any transparency at all, the foreground color is applied to all pixels in the image.
        Semitransparent pixels also get the same color but maintain their alpha value. When bg color is changed in this situation, nothing happens. 
		- If the image is a full image with no transparency, then:
			The foreground color will change the color of everything EXCEPT the first color found in the image.
			The background color will change the color of only pixels that were the first color found in the image. ]]--

local function apply_selected_colors_to_image(image, apply_foreground, apply_background)

	local current_fgcolor = convert_color_to_app_pixelcolor(app.fgColor)
	local current_bgcolor = convert_color_to_app_pixelcolor(app.bgColor)
	
	local closest_fg = get_closest_color_in_palette(current_fgcolor)
	local closest_bg = get_closest_color_in_palette(current_bgcolor)
	
	if app.activeSprite.colorMode == ColorMode.INDEXED then
		current_fgcolor = closest_fg
		current_bgcolor = closest_bg
	elseif app.activeSprite.colorMode == ColorMode.GRAY then 
		current_fgcolor = app.pixelColor.graya(current_fgcolor)
		current_bgcolor = app.pixelColor.graya(current_bgcolor)
	end
	
	local image_has_transparency = does_image_have_transparency(image)
	
	-- Image transparent, so just apply the foreground color if applicable
	if image_has_transparency then
		
		if apply_foreground == false then
			return
		end
		
		color_whole_image_rgb(image, current_fgcolor)
	else
		local first_color = nil -- First color in the image, starting from the top left 
		local second_color = nil  -- Second color in the image, starting from the top left
		
		for it in image:pixels() do
			local pixelValue = it()
			
			-- Determine the first and second colors in the image
			if first_color == nil then
				first_color = pixelValue
			elseif (second_color == nil and pixelValue ~= first_color) then 
				second_color = pixelValue
			end
			
			-- Apply the fgcolor to any pixels that are not the first color found in the image
			if (apply_foreground and second_color ~= nil and pixelValue ~= first_color) then 
				it(current_fgcolor)
			elseif (apply_background and first_color ~= nil and pixelValue == first_color) then 
				it(current_bgcolor)
			end 
			
		end
	end 
	
end 

local function convert_color_to_colormode(pixelColor)
	
	if color_mode == ColorMode.RGB then
		local a = app.pixelColor.rgbaA(pixelColor)
		
		
		if app.activeSprite.colorMode == ColorMode.INDEXED then 
			if a == 0 then 
				return app.activeSprite.spec.transparentColor
			end
			
			return get_closest_color_in_palette(pixelColor)
		elseif app.activeSprite.colorMode == ColorMode.GRAY then 
			return app.pixelColor.graya(pixelColor)
		end
	
	elseif color_mode == ColorMode.GRAY then 
		local value = app.pixelColor.grayaV(pixelColor)
		local a = app.pixelColor.grayaA(pixelColor)
		
		if app.activeSprite.colorMode == ColorMode.RGB then 
			return app.pixelColor.rgba(value, value, value, a)
		elseif app.activeSprite.colorMode == ColorMode.INDEXED then 
			
			return get_closest_color_in_palette(app.pixelColor.rgba(value, value, value, a))
		end
	elseif color_mode == ColorMode.INDEXED then 
	
		if pixelColor == app.activeSprite.spec.transparentColor then 
			return app.pixelColor.rgba(0, 0, 0, 0)
		end
		
		local non_indexed_color = convert_color_to_app_pixelcolor(app.activeSprite.palettes[1]:getColor(pixelColor))
		
		local r = app.pixelColor.rgbaR(non_indexed_color)
		local g = app.pixelColor.rgbaG(non_indexed_color)
		local b = app.pixelColor.rgbaB(non_indexed_color)
		local a = app.pixelColor.rgbaA(non_indexed_color)

		if app.activeSprite.colorMode == ColorMode.RGB then
			return non_indexed_color
		elseif app.activeSprite.colorMode == ColorMode.GRAY then
			return app.pixelColor.graya(non_indexed_color)
		end
	end
end

local function convert_image_to_colormode(image) 
	local new_image = Image(image.width, image.height, app.activeSprite.colorMode)
	
	for it in new_image:pixels() do
		local oldValue = image:getPixel(it.x, it.y)
		local new_pixelValue = convert_color_to_colormode(oldValue)
		
		
		it(new_pixelValue) -- Set pixel

		
	end
	
	return new_image
end

local function convert_base_images_to_colormode()
	for i = 0, #base_images do
		base_images[i] = convert_image_to_colormode(base_images[i])
	end
end

app.events:on('sitechange',
  function()
	if sprite ~= nil then
		sprite.events:off(on_sprite_change)
	end 
	sprite = app.activeSprite
	
	if sprite ~= nil then
		
		sprite.events:on('change', on_sprite_change)
		
		if color_mode ~= app.activeSprite.colorMode then
			convert_base_images_to_colormode()
			recolored_base_images = {}
			color_mode = app.activeSprite.colorMode
		end
	end
	
  end)


-- Detects if a new brush is found --
-- Called any time the user interacts with the widgets or changes fgcolor or bgcolor --
local function detect_new_brush_and_update()
	-- Scale up the base image to the previous scale, and compare alphas. If they are the same, it's the same brush
	
	if color_mode ~= app.activeSprite.colorMode then
		convert_base_images_to_colormode()
		recolored_base_images = {}
		color_mode = app.activeSprite.colorMode
	end
	

	local former_slider_val_percent_x = 0
	local former_slider_val_percent_y = 0
	local width = 0
	local height = 0
	local base_copy = nil
	
	if base_images[current_image_index] ~= nil then	
		former_slider_val_percent_x = last_image_scale_x / 100
		former_slider_val_percent_y = last_image_scale_y / 100
		base_copy = base_images[current_image_index]:clone()
		
		width = math.floor(base_copy.width * former_slider_val_percent_x)
		height = math.floor(base_copy.height * former_slider_val_percent_y)
		
		base_copy:resize(width, height)
		
		if rotation ~= 0 then
			base_copy = rotate_image(base_copy, -rotation)
		end
		
	end
	
	if (image_alpha_comparison(app.activeBrush.image, base_copy) == false or base_images[current_image_index] == nil) then
		-- Update the brush parameters, as we've switched brushes entirely since the last update -- 
		
		base_images = {}
		current_image_index = 0
		base_images[current_image_index] = app.activeBrush.image
		
		recolored_base_images = {}
		fgcolor_changed = false
		bgcolor_changed = false 
		
		dlg:modify {id = "flipx",
			selected = false }
			
		dlg:modify {id = "flipy",
			selected = false }
			
		rotation = 0
	end
	
end


-- Resets the brush to the base brush, setting the scale & color back to the original -- 
function reset_brush()

	-- If the brush isn't an image brush we want nothing to do with it
	if app.activeBrush.type ~= BrushType.IMAGE then
		return
	end
	
	detect_new_brush_and_update()

	app.activeBrush = Brush(base_images[0])
	current_image_index = 0
	recolored_base_images = {}
	
	dlg:modify {id = "flipx",
			selected = false }
			
	dlg:modify {id = "flipy",
			selected = false }
			
	rotation = 0

	last_image_scale_x = 100
	last_image_scale_y = 100
	resized_last_update = false
	fgcolor_changed = false
	bgcolor_changed = false
	
end




local function randomize_size()
	local min_size = dlg.data.randsizemin
	local max_size = dlg.data.randsizemax
	
	local size = math.random(min_size, max_size)
	
	dlg:modify {id = "size_x",
			value = size }
	
	if dlg.data.check == true then 
		dlg:modify {id = "size_y",
			value = size }
	else 
		local size_y = math.random(min_size, max_size)
		dlg:modify {id = "size_y",
			value = size_y }
	end 
end 

local function get_random_offset()
	local max_offset = dlg.data.randoffsetlength
	
	local offset = math.random(0, max_offset)
	
	local rand_angle = math.random() * math.pi * 2
	local offset_x = math.cos(rand_angle) * offset
	local offset_y = math.sin(rand_angle) * offset
	
	return Point(offset_x, offset_y)
end 


-- Resizes the current brush based on the current slider values --
local function resize_brush()


	local slider_val_x = dlg.data.size_x
	local slider_val_y = dlg.data.size_y
	
	local image_copy
	-- If we've got a recolored image (from changing fg/bgcolor) then use that instead of the base
	if recolored_base_images[current_image_index] ~= nil then
		image_copy = recolored_base_images[current_image_index]:clone()
	else
		image_copy = base_images[current_image_index]:clone()
	end 
	
	local slider_val_x_percent = slider_val_x / 100
	local slider_val_y_percent = slider_val_y / 100
	
	
	local width = math.floor(image_copy.width * slider_val_x_percent)
	local height = math.floor(image_copy.height * slider_val_y_percent)
	
	image_copy:resize(width, height)
	
	if dlg.data.flipx == true or dlg.data.flipy == true then
		image_copy = get_flipped_image(image_copy, dlg.data.flipx, dlg.data.flipy)
	end
	
	if rotation ~= 0 then
		image_copy = rotate_image(image_copy, rotation)
	end
	
	
	resized_last_update = true
	
	if dlg.data.randoffsetcheck == false then
		curr_offset = Point(image_copy.width / 2, image_copy.height / 2)
	
	end

	--app.activeBrush = Brush(image_copy)
	app.activeBrush = Brush{
		type = BrushType.IMAGE,
		center = curr_offset,
		image = image_copy
	}
	
	last_image_scale_x = slider_val_x
	last_image_scale_y = slider_val_y
end


dlg:slider {
    id = "size_x",
    label = "Width (%): ",
    min = 1,
    max = 200,
    value = 100,
	onchange = function()
	
		if dlg.data.check == true then 
			dlg:modify {id = "size_y",
			value = dlg.data.size_x }
		end
	
		-- If the brush isn't an image brush we want nothing to do with it
		if app.activeBrush.type ~= BrushType.IMAGE then
			return
		end
		
		detect_new_brush_and_update()
	
		resize_brush()
			
	end
}

dlg:slider {
    id = "size_y",
    label = "Height (%): ",
    min = 1,
    max = 200,
    value = 100,
	onchange = function()
	
		if dlg.data.check == true then 
			dlg:modify {id = "size_x",
			value = dlg.data.size_y }
		end 
		
		-- If the brush isn't an image brush we want nothing to do with it
		if app.activeBrush.type ~= BrushType.IMAGE then
			return
		end
		
		detect_new_brush_and_update()
	
		resize_brush()
			
	end
}

dlg:check {
	id = "check",
	label = string,
	text = "Keep aspect",
	selected = boolean,
	onclick = function()
		if app.activeBrush.type ~= BrushType.IMAGE then
			return
		end
		
		detect_new_brush_and_update()
		
		if dlg.data.check == true then 
			dlg:modify {id = "size_y",
			value = dlg.data.size_x }
		end 
		
		resize_brush()
	end
}

dlg:check {
	id = "flipx",
	label = string,
	text = "Flip X",
	selected = boolean,
	onclick = function()
		if app.activeBrush.type ~= BrushType.IMAGE then
			return
		end

	
		detect_new_brush_and_update()
		
		resize_brush()
	end
}

dlg:check {
	id = "flipy",
	label = string,
	text = "Flip Y",
	selected = boolean,
	onclick = function()
		if app.activeBrush.type ~= BrushType.IMAGE then
			return
		end
	
		detect_new_brush_and_update()
		
		resize_brush()
	end
}

dlg:button {
	id = "rotate",
	text = "Rotate 90 CW",
	onclick = function()
	
		if app.activeBrush.type ~= BrushType.IMAGE then
			return
		end
		
		detect_new_brush_and_update()
		
		rotation = rotation - 90
		
		if rotation == -360 then rotation = 0 end
		
		resize_brush()
	end 
}

dlg:button {
	id = "rotate",
	text = "Rotate 90 CCW",
	onclick = function()
	
		if app.activeBrush.type ~= BrushType.IMAGE then
			return
		end
		
		detect_new_brush_and_update()
		
		rotation = rotation + 90
		
		if rotation == 360 then rotation = 0 end
		
		resize_brush()
	end 
}




-- When the fgcolor/bgcolor change, we want to store a version of the brush image at the original image scale

function on_fgcolorchange()
	if app.activeSprite.colorMode == ColorMode.INDEXED then
		app.fgColor = get_closest_color_in_palette(convert_color_to_app_pixelcolor(app.fgColor))
	end 

	-- If the brush isn't an image brush we want nothing to do with it
	if app.activeBrush.type ~= BrushType.IMAGE then
		return
	end
	
	detect_new_brush_and_update()

	fgcolor_changed = true
	for i = 0, #base_images do
		recolored_base_images[i] = base_images[i]:clone()
		apply_selected_colors_to_image(recolored_base_images[i], fgcolor_changed, bgcolor_changed)
	end
		
end

function on_bgcolorchange()

	if app.activeSprite.colorMode == ColorMode.INDEXED then
		app.bgColor = get_closest_color_in_palette(convert_color_to_app_pixelcolor(app.bgColor))
	end 
	-- If the brush isn't an image brush we want nothing to do with it
	if app.activeBrush.type ~= BrushType.IMAGE then
		return
	end
	
	detect_new_brush_and_update() -- So we save the new brush here, but it's already a different color
	
	bgcolor_changed = true
	
	
	for i = 0, #base_images do
		recolored_base_images[i] = base_images[i]:clone()
		apply_selected_colors_to_image(recolored_base_images[i], fgcolor_changed, bgcolor_changed)
	end
	
	
end


app.events:on('fgcolorchange', on_fgcolorchange)
	
app.events:on('bgcolorchange', on_bgcolorchange)

function on_sprite_change()
	if app.activeBrush.type ~= BrushType.IMAGE then
		return
	end

	detect_new_brush_and_update()
	
	-- If we've got multiple brushes, change to either the next brush or a random one --
	if #base_images > 0 then
	
		if dlg.data.randomizebrush == true then 
			current_image_index = math.random(0, #base_images)
		else
			current_image_index = current_image_index + 1
			if current_image_index > #base_images then 
				current_image_index = 0
			end 
		end
	else
		current_image_index = 0
	end
	
	if dlg.data.randsizecheck then 
		randomize_size()
	end
	
	if dlg.data.randoffsetcheck then 
		curr_offset = get_random_offset()
	end 
	
	resize_brush()
	
end

sprite.events:on('change', on_sprite_change) 

local function point_in_rectangle(x, y, rectangle)
	if (x >= rectangle.x and x <= rectangle.x + rectangle.width and y >= rectangle.y and y <= rectangle.y + rectangle.height) then 
		return true
	end 
	
	return false
end

local function get_image_from_rect(rect)
	local image = Image(rect.width, rect.height, app.activeSprite.colorMode)

	local current_image = app.activeImage
	local image_bounds = current_image.cel.bounds
	
	for y = rect.y, rect.y + rect.height do
		for x = rect.x, rect.x + rect.width do
		
			local point_rel_imagebound = Point(x - image_bounds.x, y - image_bounds.y)
			
			if point_rel_imagebound.x >= 0 and point_rel_imagebound.y >= 0 and point_rel_imagebound.x < image_bounds.width and point_rel_imagebound.y < image_bounds.height then 
				local pixelValue = current_image:getPixel(x - image_bounds.x, y - image_bounds.y)
				local c = get_pxc_as_color(pixelValue)
				image:drawPixel(x - rect.x, y - rect.y, pixelValue)
			end
		end 
	end
			
	return image
	
	
end

dlg:separator{ id=string,
               label=string,
               text=string }

dlg:newrow()

-- Random size ui --

dlg:newrow { always = false }	

dlg:check {
	id = "randsizecheck",
	label = "Randomize size",
	text = string,
	selected = boolean

}

dlg:number{ id="randsizemin",
            label="Min size %",
            text="50",
            decimals=50
			}

dlg:number{ id="randsizemax",
            label="Max size %",
            text="100",
            decimals=100
			}
		
dlg:separator{ id=string,
               label=string,
               text=string }

dlg:newrow()

dlg:check {
	id = "randoffsetcheck",
	label = "Randomize offset",
	text = string,
	selected = boolean, 
	onclick = function() 
	
		if dlg.data.randoffsetcheck == false then
			curr_offset = Point(0, 0)
			resize_brush()
		end
		
	end
}

dlg:slider {
    id = "randoffsetlength",
    label = "Offset amount",
    min = 0,
    max = 100,
    value = 20,

}


dlg:separator{ id=string,
               label=string,
               text=string }
  
dlg:button{ id="brush_start",
            label=string,
            text="Brushes from selection",
            selected=boolean,
            focus=boolean,
            onclick=function()
			
				if app.activeImage == nil or app.activeSprite.selection == nil then
	
					return 
				end
				
				current_image_index = 0
				detect_new_brush_and_update()
				
				base_images = {}
			
				--[[ Loop through the entire selection and find the start and end points of each subselection
				When we hit a pixel that is in the selection and is not within the bounds of any already saved subselections, then 
				that is the first pixel of a new selection. Then, loop through the x until we find the right side of that selection, and then 
				loop through the y until we find the bottom right point. Then save that pair of points and continue. ]]--
				
				local subselections = {}
				local subselection_count = 0
				
				local subselection_start
				
				local selection = app.activeSprite.selection
				-- selection.bounds.width
				for y = 0, selection.bounds.height do -- Would be width-1, but we want to test a pixel on the outside so for subselections on the right we can find the end
					for x = 0, selection.bounds.width do
						
						-- Check if we should skip this point because we've already found this selection
						local point_in_existing_subselection = false
						for i = 1, #subselections do
							if point_in_rectangle(selection.bounds.x + x, selection.bounds.y + y, subselections[i]) then 
								point_in_existing_subselection = true
								break
							end 
						end
						
						
						if point_in_existing_subselection then
							goto continue
						end
					
						
						if (point_in_existing_subselection == false and selection:contains(selection.bounds.x + x, selection.bounds.y + y)) then
							subselection_start = Point(x, y)
							
							
							local end_x = 0
							-- Find the right side of the rect 
							for x2 = x, selection.bounds.width do
						
								if selection:contains(selection.bounds.x + x2, selection.bounds.y + y) == false then
									end_x = x2 - 1
									break
								end
							end
							
							local end_y = 0
							-- Find the bottom of the rect
							for y2 = y, selection.bounds.height do
								
								if selection:contains(selection.bounds.x + end_x, selection.bounds.y + y2) == false then
									end_y = y2 - 1
									break
								end
							end
							
							
							-- Add subselection
							local rect = Rectangle(selection.bounds.x + x, selection.bounds.y + y, (end_x - x + 1), (end_y - y + 1))
							subselection_count = subselection_count + 1
							subselections[subselection_count] = rect
							
			
						end 
						
						if subselection_count >= brush_cap then 
							break
						end
						
						::continue::
					end
					
					if subselection_count >= brush_cap then 
							break
						end
					
				end
				
				local image_count = 0
				for i = 1, #subselections do
					local image = get_image_from_rect(subselections[i])
					base_images[image_count] = image
					image_count = image_count + 1
				end
				
				recolored_base_images = {}

				if image_count > 0 then 
					resize_brush()
				end
				
			end
			}  

dlg:newrow()

dlg:check {
	id = "randomizebrush",
	label = string,
	text = "Randomize brush order",
	selected = boolean,
	onclick = function()
		if app.activeBrush.type ~= BrushType.IMAGE then
			return
		end
	
		detect_new_brush_and_update()
		
		resize_brush()
	end }
	

dlg:newrow()
			
dlg:button {
	id = "reset",
	text = "Reset brush",
	onclick = function()
		dlg:modify {id = "size_x",
			value = 100 }
		dlg:modify {id = "size_y",
			value = 100 }

		reset_brush()
	end 
}

dlg:show { 
	wait = false
}