package main

import "core:fmt"
import "core:strings"
import "core:math"
import "core:mem"
import rl "vendor:raylib"

// All lengths are in pixels

// Screen
SCREEN_WIDTH :: 1280 
SCREEN_HEIGHT :: 720

BACKGROUND_COLOR :: rl.WHITE

// Finish Line
FINISH_LINE_SIDE_LENGTH :: 10

// Guy
Guy :: struct {
	age: f32,
	using position: rl.Vector2,
	direction: rl.Vector2
}

GUY_LIFESPAN : f32 : 0.8
GUY_RADIUS :: 2
GUY_SPEED :: 300
GUY_COLOR :: rl.BLACK

// Main Guy
MainGuy :: struct {
	using position: rl.Vector2,
	isPulsing: bool,
	isReversing: bool,
	path: [dynamic]MainGuyPathNode,
}

MainGuyPathNode :: struct {
	using position: rl.Vector2,
	type: MainGuyPathNodeType,
}

MainGuyPathNodeType :: enum {
	Path,
	Ping,
	Collision
}

MGUY_SPEED :: 175
MGUY_SIDE_LENGTH :: 6
MGUY_COLOR :: rl.BLACK
MGUY_START_POSITION :: rl.Vector2 { f32(SCREEN_WIDTH * -1 / 2) + 100, 0 }

MGUY_PATH_SAMPLE_TIME: f32 : 0.05 // in seconds
MGUY_PATH_SAMPLE_COLOR :: rl.PINK
MGUY_PATH_SAMPLE_RADIUS : f32 : 2
MGUY_PATH_SAMPLE_MIN_DISTANCE : f32 : .05 // The lower bound on distance before the two are touching

MGUY_PATH_PING_COLOR :: rl.RED
MGUY_PATH_PING_RADIUS :: 6

MGUY_COLLISION_COLOR :: rl.BLUE
MGUY_COLLISION_SIDE_LENGTH :: 12

MGUY_REVERSAL_TIME : f32 : .8 // in seconds
MGUY_REVERSAL_SPEED_MULTIPLIER : f32 : 2

// Obstacles
OBSTACLE_COLOR :: rl.BLACK

// Game Loop
GameState :: enum {
	Drawing,
	Playing, 
	Finished
}

END_MESSAGE : cstring : "GAME OVER"

main :: proc() {
	rl.InitWindow(SCREEN_WIDTH, SCREEN_HEIGHT, "ping draft")	
	rl.HideCursor()

	game_state := GameState.Drawing

	obstacles: [dynamic]rl.Rectangle

	current_obstacle_corner1: rl.Vector2	
	current_obstacle_corner2: rl.Vector2
	making_obstacle := false

	finish_line: rl.Vector2
	valid_finish_line_placement: bool

	guys: [dynamic]Guy

	main_guy := MainGuy {
		position = MGUY_START_POSITION, 
		isPulsing = false,
		isReversing = false,	
	}

	timer: f32 = 0
	reversal_timer: f32 = 0

	collision_punishes := true

	win := false

	for !rl.WindowShouldClose() {
		rl.BeginDrawing()
		rl.ClearBackground(BACKGROUND_COLOR)
		defer rl.EndDrawing()	

		{ // Input
			{ // Keyboard
				using rl.KeyboardKey

				if (rl.IsKeyDown(.SPACE) && !main_guy.isPulsing && !main_guy.isReversing) && game_state == GameState.Playing {
					main_guy.isPulsing = true
					guys = make_guys(main_guy.position)

					new_ping := MainGuyPathNode {
						rl.Vector2 { main_guy.x, main_guy.y },
						MainGuyPathNodeType.Ping
					}
					append(&main_guy.path, new_ping)
				}

				move_direction := rl.Vector2(0)

				if rl.IsKeyDown(.W) { move_direction += rl.Vector2 { 0, 1 } }
				if rl.IsKeyDown(.A) { move_direction += rl.Vector2 { -1, 0 } }
				if rl.IsKeyDown(.S) { move_direction += rl.Vector2 { 0, -1 } }
				if rl.IsKeyDown(.D) { move_direction += rl.Vector2 { 1, 0 } }

				if (move_direction.x != 0 || move_direction.y != 0) && game_state == GameState.Playing && !main_guy.isReversing {
					if move_mguy(move_direction, &main_guy, &obstacles) && collision_punishes {
						append(&main_guy.path, MainGuyPathNode { main_guy.position, MainGuyPathNodeType.Collision })

						main_guy.isReversing = true
						reversal_timer = 0
					}
				}

				if rl.IsKeyPressed(.P) && !is_v2_within_obstacles(finish_line, &obstacles) {
					game_state = GameState.Playing
				}

				if rl.IsKeyPressed(.F) && game_state == GameState.Playing {
					fmt.println("forfeited")
					win = false
					end_play(win, &game_state, &main_guy, &guys)
				}

				if rl.IsKeyPressed(.C) {
					collision_punishes = !collision_punishes

					if collision_punishes { fmt.println("collision now punishes") }
					else { fmt.println("collision no longer punishes") }
				}

			}

			{ // Mouse
				if rl.IsMouseButtonPressed(rl.MouseButton.LEFT) && game_state == GameState.Drawing { // Handle making a new obstacle
					if making_obstacle {
						new_rect := make_rectangle_from_corners(current_obstacle_corner1, current_obstacle_corner2)

						if !is_mguy_colliding_with_obstacle(&main_guy, &new_rect) {
							append(&obstacles, new_rect)

							making_obstacle = false
						}
					} 
					else {
						current_obstacle_corner1 = rl.Vector2 {
							real_x_to_world(f32(rl.GetMouseX())),
							real_y_to_world(f32(rl.GetMouseY()))
						}

						making_obstacle = true
					}
				}

				if making_obstacle { // update corner 2 if obstacle is being made
					current_obstacle_corner2 = rl.Vector2 {
						real_x_to_world(f32(rl.GetMouseX())),
						real_y_to_world(f32(rl.GetMouseY()))
					}
				}

				if rl.IsMouseButtonPressed(rl.MouseButton.RIGHT) {
					if making_obstacle {
						making_obstacle = false
					}

					if game_state == GameState.Drawing {
						mouse_x := real_x_to_world(f32(rl.GetMouseX()))
						mouse_y := real_y_to_world(f32(rl.GetMouseY()))

						for i := 0; i < len(obstacles); i += 1 {
							if is_v2_within_obstacle(rl.Vector2 { mouse_x, mouse_y }, obstacles[i]) {
								unordered_remove(&obstacles, i)
								continue
							}
						}
					}
				}

				if game_state == GameState.Drawing {
					finish_line.x = real_x_to_world(f32(rl.GetMouseX()))
					finish_line.y = real_y_to_world(f32(rl.GetMouseY()))
				}

				if game_state == GameState.Finished { rl.ShowCursor() }
				else { rl.HideCursor() }

				valid_finish_line_placement = !is_v2_within_obstacles(finish_line, &obstacles)
			}

		}

		{ // Guys
			for i := 0; i < len(guys); i += 1 {
				{ // Update 
					if update_guy(&guys[i], &obstacles) {
						main_guy.isPulsing = false
						unordered_remove(&guys, i)

						continue
					}
				}

				{ // Render
					render_guy(&guys[i])
				}
			}
		}

		{ // Main Guy
			if game_state != GameState.Finished { // Render
				render_mguy(&main_guy)

				if is_mguy_colliding_with_finish_line(&main_guy, finish_line) && game_state == GameState.Playing {
					win = true
					end_play(win, &game_state, &main_guy, &guys)
				}
			}

			if timer > MGUY_PATH_SAMPLE_TIME {
				if game_state == GameState.Playing { // TODO; the sampling timer should start on game_state == Playing
					new_path := MainGuyPathNode { rl.Vector2 { main_guy.x, main_guy.y }, MainGuyPathNodeType.Path }
					append(&main_guy.path, new_path)
				}

				timer = 0
			}

			if main_guy.isReversing && reversal_timer < MGUY_REVERSAL_TIME {
				move_mguy_towards_last_path_node(&main_guy)

				reversal_timer += rl.GetFrameTime()
			}
			else if reversal_timer > MGUY_REVERSAL_TIME { 
				main_guy.isReversing = false
			}
		}

		{ // Obstacles
			if game_state != GameState.Playing {
				for i := 0; i < len(obstacles); i += 1{
					{ // Render
						render_obstacle(&obstacles[i])
					}
				}

				if making_obstacle {
					c1_x := world_x_to_real(current_obstacle_corner1.x)
					c1_y := world_y_to_real(current_obstacle_corner1.y)

					c2_x := world_x_to_real(current_obstacle_corner2.x)
					c2_y := world_y_to_real(current_obstacle_corner2.y)

					rl.DrawLineV(rl.Vector2 {c1_x, c2_y}, rl.Vector2 {c2_x, c2_y}, rl.BLUE)
					rl.DrawLineV(rl.Vector2 {c1_x, c1_y}, rl.Vector2 {c2_x, c1_y}, rl.BLUE)
					rl.DrawLineV(rl.Vector2 {c1_x, c2_y}, rl.Vector2 {c1_x, c1_y}, rl.BLUE)
					rl.DrawLineV(rl.Vector2 {c2_x, c1_y}, rl.Vector2 {c2_x, c2_y}, rl.BLUE)
				}
			}
		}

		{ // Finish Line
			// Always getting rendered
			finish_line_real := world_v2_to_real(finish_line)
			finish_line_real -= FINISH_LINE_SIDE_LENGTH / 2

			rl.DrawRectangleV(finish_line_real, rl.Vector2 { FINISH_LINE_SIDE_LENGTH, FINISH_LINE_SIDE_LENGTH }, rl.ColorAlpha(rl.GREEN, valid_finish_line_placement ? 1.0 : .15))
		}

		if game_state == GameState.Finished { // Game over stuff
			{ // End message text
				font := rl.GetFontDefault() 
				font_size: f32 = 50

				text_size := rl.MeasureTextEx(font, END_MESSAGE, font_size, 1)
				rl.DrawText(END_MESSAGE, (rl.GetScreenWidth() / 2) - i32(text_size.x / 2), (rl.GetScreenHeight() / 2) - i32(text_size.y / 2), i32(font_size), rl.BLACK)
			}

			{ // Path
				for i := 0; i < len(main_guy.path); i += 1 {
					draw_path_node(&main_guy.path[i])
				}
			}

			{ // Buttons
				if rl.GuiButton( rl.Rectangle { 10, 10, 100, 100 }, "Done") {
					break
				}

				if rl.GuiButton(rl.Rectangle { 120, 120, 100, 100 }, "Play Again") {
					game_state = GameState.Drawing
					clear_for_new_game(&obstacles, &main_guy)
				}
			}
		}

		timer += rl.GetFrameTime()
	}

	rl.CloseWindow()
}

move_mguy_towards_last_path_node :: proc(main_guy: ^MainGuy) {
	last_path_sample_index := -1
	for i := len(main_guy.path) - 1; i >= 0; i -= 1 {
		current_node := main_guy.path[i]

		if current_node.type != MainGuyPathNodeType.Path { continue }

		if math.abs(rl.Vector2Distance(current_node.position, main_guy.position)) > MGUY_PATH_SAMPLE_MIN_DISTANCE { // If this path node is not too close to main guy, it's the next
			last_path_sample_index = i
			break
		}
		else { // This path node is too close, should be removed
			ordered_remove(&main_guy.path, i) // Gotta be ordered, effectively using this as a stack with some nodes that aren't considered
		}
	}

	if last_path_sample_index == -1 { return }
	// TODO move the logic above to it's own procedure

	target := main_guy.path[last_path_sample_index]

	direction := rl.Vector2Normalize(target - main_guy.position)

	main_guy.position += direction * MGUY_REVERSAL_SPEED_MULTIPLIER * MGUY_SPEED * rl.GetFrameTime()
}

draw_path_node :: proc(node: ^MainGuyPathNode) {
	node_real := world_v2_to_real(node.position)

	switch node.type {
		case .Path:
			rl.DrawCircle(i32(node_real.x), i32(node_real.y), MGUY_PATH_SAMPLE_RADIUS, MGUY_PATH_SAMPLE_COLOR)
		case .Ping:
			rl.DrawCircle(i32(node_real.x), i32(node_real.y), MGUY_PATH_PING_RADIUS, MGUY_PATH_PING_COLOR)
		case .Collision:
			node_real -= MGUY_COLLISION_SIDE_LENGTH / 2
			rl.DrawRectangle(i32(node_real.x), i32(node_real.y), MGUY_COLLISION_SIDE_LENGTH, MGUY_COLLISION_SIDE_LENGTH, MGUY_COLLISION_COLOR)
	}
}

clear_for_new_game :: proc(obstacles: ^[dynamic]rl.Rectangle, main_guy: ^MainGuy) {
	clear(obstacles)
	clear(&main_guy.path)
}

end_play :: proc(win: bool, state: ^GameState, main_guy: ^MainGuy, guys: ^[dynamic]Guy) {
	clear(guys)

	main_guy.position = MGUY_START_POSITION
	main_guy.isPulsing = false
	main_guy.isReversing = false

	state^ = GameState.Finished
}

is_v2_within_obstacle :: proc(v: rl.Vector2, obstacle: rl.Rectangle) -> bool {
	return v.x > obstacle.x && v.x < obstacle.x + obstacle.width && v.y > obstacle.y && v.y < obstacle.y + obstacle.height
}

is_v2_within_obstacles :: proc(v: rl.Vector2, obstacles: ^[dynamic]rl.Rectangle) -> bool {
	for i := 0; i < len(obstacles); i += 1 {
		if is_v2_within_obstacle(v, obstacles[i]) { return true }
	}

	return false
}

is_mguy_colliding_with_finish_line :: proc(main_guy: ^MainGuy, finish_line: rl.Vector2) -> bool {
	finish_line_rect := rl.Rectangle {
		finish_line.x - FINISH_LINE_SIDE_LENGTH / 2,
		finish_line.y - FINISH_LINE_SIDE_LENGTH / 2,
		FINISH_LINE_SIDE_LENGTH,
		FINISH_LINE_SIDE_LENGTH,
	}

	return is_mguy_colliding_with_obstacle(main_guy, &finish_line_rect)
}

make_rectangle_from_corners :: proc(c1: rl.Vector2, c2: rl.Vector2) -> rl.Rectangle {
	corner_x := c1.x
	corner_y := c1.y

	width := c2.x - c1.x
	height := c2.y - c1.y

	if c1.x > c2.x {
		corner_x = c2.x
		width = c1.x - c2.x
	}

	if c1.y > c2.y {
		corner_y = c2.y
		height = c1.y - c2.y
	}

	return rl.Rectangle {
		corner_x, 
		corner_y, 
		width,
		height,
	}
}

world_v2_to_real :: proc(v: rl.Vector2) -> rl.Vector2 {
	return rl.Vector2 {
		world_x_to_real(v.x),
		world_y_to_real(v.y)
	}
}

real_v2_to_world :: proc(v: rl.Vector2) -> rl.Vector2 {
	return rl.Vector2 {
		real_x_to_world(v.x),
		real_y_to_world(v.y)
	}
}

real_x_to_world :: proc(x: f32) -> f32 {
	return x - f32(rl.GetScreenWidth() / 2)  
}

real_y_to_world :: proc(y: f32) -> f32 {
	return f32(rl.GetScreenHeight() / 2) - y 
}

render_obstacle :: proc(obstacle: ^rl.Rectangle) {
	real_rec_corner := world_to_real_space(rl.Vector2 { obstacle.x, obstacle.y + obstacle.height })

	rl.DrawRectangleRec(rl.Rectangle { real_rec_corner.x, real_rec_corner.y, obstacle.width, obstacle.height }, rl.ColorAlpha(OBSTACLE_COLOR, 0.1))
}

render_mguy :: proc(main_guy: ^MainGuy) {
	real_position := world_to_real_space(main_guy.position)

	real_x := i32(real_position.x - MGUY_SIDE_LENGTH / 2)
	real_y := i32(real_position.y - MGUY_SIDE_LENGTH / 2)

	rl.DrawRectangle(real_x, real_y, MGUY_SIDE_LENGTH, MGUY_SIDE_LENGTH, MGUY_COLOR)
}

world_to_real_space :: proc(world_coord: rl.Vector2) -> rl.Vector2 {
	return rl.Vector2 {
		world_x_to_real(world_coord.x),
		world_y_to_real(world_coord.y)
	}
}

world_x_to_real :: proc(x: f32) -> f32 {
	return f32(rl.GetScreenWidth() / 2) + x
}

world_y_to_real :: proc(y: f32) -> f32 {
	return f32(rl.GetScreenHeight() / 2) - y
}

render_guy :: proc(guy: ^Guy) {
	center := world_to_real_space(guy.position)
	rl.DrawCircle(i32(center.x), i32(center.y), GUY_RADIUS, rl.ColorAlpha(GUY_COLOR, guy_fade_away_alpha(guy.age)))
}

move_mguy :: proc(direction: rl.Vector2, main_guy: ^MainGuy, obstacles: ^[dynamic]rl.Rectangle) -> bool {
	new_mguy := MainGuy {
		position = main_guy.position + rl.Vector2Normalize(direction) * rl.GetFrameTime() * MGUY_SPEED,
	}

	half_side_length: f32 = MGUY_SIDE_LENGTH / 2
	if !is_mguy_colliding_with_obstacles(&new_mguy, obstacles) && new_mguy.x + half_side_length < f32(rl.GetScreenWidth() / 2) && new_mguy.x - half_side_length > -1 * f32(rl.GetScreenWidth() / 2) && new_mguy.y + half_side_length < f32(rl.GetScreenHeight() / 2) && new_mguy.y - half_side_length > -1 * f32(rl.GetScreenHeight() / 2) {
		main_guy.position = new_mguy.position
		return false
	}
	else { 
		fmt.println("colliding ", rl.GetTime())
		return true 
	}
}

is_mguy_colliding_with_obstacles :: proc(main_guy: ^MainGuy, obstacles: ^[dynamic]rl.Rectangle) -> bool {
	for i := 0; i < len(obstacles); i += 1 {
		if is_mguy_colliding_with_obstacle(main_guy, &obstacles[i]) { return true }
	}

	return false
}

is_mguy_colliding_with_obstacle :: proc(main_guy: ^MainGuy, obstacle: ^rl.Rectangle) -> bool {
	mguy_rectangle := rl.Rectangle {
		main_guy.x,
		main_guy.y,
		MGUY_SIDE_LENGTH,
		MGUY_SIDE_LENGTH
	}

	return (mguy_rectangle.x + mguy_rectangle.width >= obstacle.x) && (mguy_rectangle.x <= obstacle.x + obstacle.width) && (mguy_rectangle.y + mguy_rectangle.height >= obstacle.y) && (mguy_rectangle.y <= obstacle.y + obstacle.height)
}

update_guy :: proc(guy: ^Guy, obstacles: ^[dynamic]rl.Rectangle) -> bool {
	if guy.age > GUY_LIFESPAN { return true }

	guy.age += rl.GetFrameTime()

	if !is_guy_colliding_with_obstacles(guy, obstacles) {
		guy.position += rl.Vector2Normalize(guy.direction) * GUY_SPEED * rl.GetFrameTime()
	}

	return false
}

is_guy_colliding_with_obstacles :: proc(guy: ^Guy, obstacles: ^[dynamic]rl.Rectangle) -> bool {
	for i := 0; i < len(obstacles); i += 1 {
		if is_guy_colliding_with_obstacle(guy, obstacles[i]) { return true }
	}

	return false
}

is_guy_colliding_with_obstacle :: proc(guy: ^Guy, obstacle: rl.Rectangle) -> bool{
	test_x := guy.x
	test_y := guy.y

	if guy.x < obstacle.x { test_x = obstacle.x }
	else if guy.x > obstacle.x + obstacle.width { test_x = obstacle.x + obstacle.width }

	if guy.y < obstacle.y { test_y = obstacle.y }
	else if guy.y > obstacle.y + obstacle.height { test_y = obstacle.y + obstacle.height }

	dist_x := guy.x - test_x
	dist_y := guy.y - test_y
	distance := math.sqrt((dist_x * dist_x) + (dist_y * dist_y))

	if distance <= GUY_RADIUS {
		return true
	}

	return false
}

make_guys :: proc(origin: rl.Vector2) -> [dynamic]Guy {
	guys: [dynamic]Guy

	divisor := 360
	for i := 0; i < divisor; i += 1 {
		angle: f16 = f16(i * (360 / divisor))

		angle *= math.PI / 180

		direction := rl.Vector2 { origin.x + f32(math.cos(angle)), origin.y + f32(math.sin(angle)) } - origin

		new_guy := Guy {
			0,
			origin + 20*(direction * GUY_SPEED * rl.GetFrameTime()),
			direction
		}

		append(&guys, new_guy)
	}

	return guys
}

guy_fade_away_alpha :: proc(age: f32) -> f32 {
	cutoff: f32 = .7

	if age < GUY_LIFESPAN * cutoff {
		return 1.0 
	}

	n := age - (GUY_LIFESPAN * cutoff)

	return 1 - (n / (GUY_LIFESPAN * (1-cutoff)))
}