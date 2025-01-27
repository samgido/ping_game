package main

import "core:fmt"
import "core:strings"
import "core:math"
import rl "vendor:raylib"

BACKGROUND_COLOR :: rl.WHITE

GUY_LIFESPAN : f32 : .7
GUY_RADIUS :: 2
GUY_SPEED :: 500
GUY_COLOR :: rl.BLACK

Guy :: struct {
	age: f32,
	using position: rl.Vector2,
	direction: rl.Vector2
}

MGUY_SPEED :: 350
MGUY_SIDE_LENGTH :: 6
MGUY_COLOR :: rl.BLACK

MainGuy :: struct {
	using position: rl.Vector2,
	isPulsing: bool,
}

OBSTACLE_COLOR :: rl.BLACK

main :: proc() {
	rl.InitWindow(1280, 720, "h")	

	render_obstacles := true

	obstacles: [dynamic]rl.Rectangle

	append(&obstacles, rl.Rectangle {
		f32(rl.GetScreenWidth() * -1 / 2),
		100,
		f32(rl.GetScreenWidth()),
		200
	})

	// append(&obstacles, rl.Rectangle {
	// 	f32(rl.GetScreenWidth() * -1 / 2) + 300,
	// 	50,
	// 	250,
	// 	100
	// })

	// append(&obstacles, rl.Rectangle {
	// 	f32(rl.GetScreenWidth() * -1 / 2),
	// 	-300,
	// 	f32(rl.GetScreenWidth()),
	// 	200
	// })

	current_obstacle_corner1: rl.Vector2	
	current_obstacle_corner2: rl.Vector2
	making_obstacle := false

	guys: [dynamic]Guy

	main_guy := MainGuy {
		rl.Vector2 { f32(rl.GetScreenWidth() * -1 / 2) + 100, 0 },
		false,
	}

	for !rl.WindowShouldClose() {
		rl.BeginDrawing()
		rl.ClearBackground(BACKGROUND_COLOR)
		defer rl.EndDrawing()	

		{ // Input
			{ // Keyboard
				using rl.KeyboardKey

				if rl.IsKeyDown(.SPACE) && !main_guy.isPulsing {
					main_guy.isPulsing = true
					guys = make_guys(main_guy.position)
				}

				move_direction := rl.Vector2(0)

				if rl.IsKeyDown(.W) { move_direction += rl.Vector2 { 0, 1 } }
				if rl.IsKeyDown(.A) { move_direction += rl.Vector2 { -1, 0 } }
				if rl.IsKeyDown(.S) { move_direction += rl.Vector2 { 0, -1 } }
				if rl.IsKeyDown(.D) { move_direction += rl.Vector2 { 1, 0 } }

				if move_direction.x != 0 || move_direction.y != 0 {
					move_main_guy(move_direction, &main_guy, &obstacles)
				}

				if rl.IsKeyPressed(.R) {
					render_obstacles = !render_obstacles
				}
			}

			{ // Mouse
				if rl.IsMouseButtonPressed(rl.MouseButton.LEFT) { // Handle making a new obstacle
					if making_obstacle { 
						corner_x := current_obstacle_corner1.x
						corner_y := current_obstacle_corner1.y

						width := current_obstacle_corner2.x - current_obstacle_corner1.x
						height := current_obstacle_corner2.y - current_obstacle_corner1.y

						if current_obstacle_corner1.x > current_obstacle_corner2.x {
							corner_x = current_obstacle_corner2.x
							width = current_obstacle_corner1.x - current_obstacle_corner2.x
						}

						if current_obstacle_corner1.y > current_obstacle_corner2.y {
							corner_y = current_obstacle_corner2.y
							height = current_obstacle_corner1.y - current_obstacle_corner2.y
						}

						append(&obstacles, rl.Rectangle {
							corner_x, 
							corner_y, 
							width,
							height,
						})

						making_obstacle = false
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
			{ // Render
				render_mguy(&main_guy)
			}
		}

		{ // Obstacles
			if render_obstacles {
				for i := 0; i < len(obstacles); i += 1{
					{ // Render
						render_obstacle(&obstacles[i])
					}
				}

			}

			if making_obstacle {
				rl.DrawLineV(world_v2_to_real(current_obstacle_corner1), world_v2_to_real(current_obstacle_corner2), rl.BLUE)
			}
		}
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

move_main_guy :: proc(direction: rl.Vector2, main_guy: ^MainGuy, obstacles: ^[dynamic]rl.Rectangle) {
	new_mguy := MainGuy {
		main_guy.position + rl.Vector2Normalize(direction) * rl.GetFrameTime() * MGUY_SPEED,
		false
	}

	if !is_mguy_colliding_with_obstacles(&new_mguy, obstacles) {
		main_guy.position = new_mguy.position
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
			origin,
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