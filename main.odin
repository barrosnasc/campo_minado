package campominado

import "core:fmt"
import "core:math/rand"
import rl "vendor:raylib"

should_game_run := true


SCREEN_DIM :: 800
game_clock: f32 = 0

TileState :: enum {
	UNDISCOVERED,
	NOTHING,
	FLAG,
	NUMBER_HINT,
	REVEAL_BOMB,
	BOMB_EXPLODED,
}

BoardTile :: struct {
	using rect:  rl.Rectangle,
	state:       TileState,
	number_hint: u8,
	bomb:        bool,
}


BOARD_SIZE :: 10 + 2
NUMBER_OF_BOMBS :: 10

scatter_bombs :: proc(board: ^[BOARD_SIZE][BOARD_SIZE]BoardTile) {
	for i in 0 ..< NUMBER_OF_BOMBS {
		x := rand.float32_range(0, BOARD_SIZE)
		y := rand.float32_range(0, BOARD_SIZE)
		tile := &board[x][y]
		tile.bomb = true
	}
}
TILE_SPACING :: 0
TILE_WIDTH :: SCREEN_DIM / BOARD_SIZE - TILE_SPACING

make_board :: proc() -> [BOARD_SIZE][BOARD_SIZE]BoardTile {
	spacing := TILE_SPACING
	tile_width := TILE_WIDTH
	tile_height := tile_width
	board: [BOARD_SIZE][BOARD_SIZE]BoardTile
	for &row, x in board {
		for &tile, y in row {
			tile.state = .UNDISCOVERED
			tile.x = f32(x * tile_width + spacing)
			tile.y = f32(y * tile_height + spacing)
			tile.width = f32(tile_width - spacing)
			tile.height = f32(tile_height - spacing)
		}
	}
	return board

}

// 8 Neightboors from x,y 
neightboors_3x3 :: proc(x, y, x_size, y_size: int) -> [dynamic][2]int {
	out: [dynamic][2]int
	for i in -1 ..= 1 {
		if x + i < 0 || x + i >= x_size {continue}
		for j in -1 ..= 1 {
			if y + j < 0 || y + j >= y_size {continue}
			if x + i == x && y + j == y {continue}
			coord: [2]int = {x + i, j + y}
			append(&out, coord)

		}
	}
	return out

}


reveal :: proc(
	board: ^[BOARD_SIZE][BOARD_SIZE]BoardTile,
	bomb_board: ^[BOARD_SIZE][BOARD_SIZE]bool,
	x, y: int,
) {
	neightboors := neightboors_3x3(x, y, BOARD_SIZE, BOARD_SIZE)
	defer delete(neightboors)
	for &pos in neightboors {
		tile := &board[pos.y][pos.x]
		bomb_tile := bomb_board[pos.y][pos.x]
		if tile.state == .UNDISCOVERED && bomb_tile == false {
			if tile.number_hint > 0 {
				tile.state = .NUMBER_HINT
			} else {
				tile.state = .NOTHING
			}
		}
	}
}

set_number_hint :: proc(board: ^[BOARD_SIZE][BOARD_SIZE]BoardTile) {
	for &row, x in board {
		for &tile, y in board {
			bomb_count: u8 = 0
			neighboors := neightboors_3x3(x, y, BOARD_SIZE, BOARD_SIZE)
			defer delete(neighboors)
			for &pos in neighboors {
				tile := &board[pos.x][pos.y]
				if tile.bomb {
					bomb_count += 1
				}
			}
			board_tile := &board[x][y]
			board_tile.number_hint = bomb_count
					}
	}

}

SPRITE_SIZE :: 13
SPRITE_DIM :: 16
SPRITE_TOTAL_X :: 4
SPRITE_TOTAL_Y :: 4

get_sprite :: proc(pos: int) -> rl.Rectangle {
	using rl
	frameRec: Rectangle = Rectangle{0, 0, SPRITE_DIM, SPRITE_DIM}
	x := pos % SPRITE_TOTAL_X
	y := pos / SPRITE_TOTAL_X
	frameRec.x = f32(x * SPRITE_DIM + x * 1)
	frameRec.y = f32(y * SPRITE_DIM + y * 1)
	return frameRec
}

main :: proc() {
	using rl

	SetConfigFlags({.VSYNC_HINT})
	InitWindow(SCREEN_DIM, SCREEN_DIM, "Campo Minado")
	SetTargetFPS(60)
	defer CloseWindow()


	sprite := LoadTexture("./tile_sprite.png")
	fmt.println(sprite.format)
	board := make_board()
	scatter_bombs(&board)
	set_number_hint(&board)
	mouse_event: struct {
		x, y:  int,
		state: enum {
			EMPTY,
			FLAG,
			TRIGGER,
			HOLD,
		},
	}
	for should_game_run {
		defer mouse_event.state = .EMPTY
		// Esc or CloseWindowIcon
		if WindowShouldClose() {should_game_run = false}

		for &row, x in board {
			for &tile, y in row {
				if CheckCollisionPointRec(GetMousePosition(), tile.rect) {
					if IsMouseButtonReleased(.LEFT) {mouse_event = {x, y, .TRIGGER}}
					if IsMouseButtonPressed(.RIGHT) {mouse_event = {x, y, .FLAG}}
					if IsMouseButtonDown(.LEFT) {mouse_event = {x, y, .HOLD}}
				}
			}
		}
		if mouse_event.state != .EMPTY {
			state := &mouse_event.state
			x := mouse_event.x
			y := mouse_event.y
			tile := &board[x][y]
			fmt.println(mouse_event, tile.x, tile.y)

			#partial switch state^ {
			case .TRIGGER:
				if tile.bomb {
					fmt.println("you lose")
					tile.state = .BOMB_EXPLODED
				} else {
					reveal(&board, x, y)
				}
			case .FLAG:
				if tile.state == .FLAG {
					tile.state = .UNDISCOVERED
				} else if tile.state == .UNDISCOVERED {tile.state = .FLAG}
			case .HOLD:
			// hint(x,y,&board)
			}

		}
		//drawing

		BeginDrawing()
		// DrawRectangleRounded(rect, 0.5, 4, RED)
		text_to_show := fmt.ctprint(game_clock)
		font_size: f32 = 40
		text_dim := MeasureTextEx(GetFontDefault(), text_to_show, font_size, 40)
		DrawText(
			text_to_show,
			i32(SCREEN_DIM / 2 - text_dim.x / 2),
			i32(SCREEN_DIM / 2 - text_dim.y / 2),
			i32(font_size),
			BLACK,
		)

		for &row, x in board {
			for &tile, y in row {
				color_to_use: rl.Color

				sprite1: Rectangle

				switch tile.state {
				case .UNDISCOVERED:
					sprite1 = get_sprite(0)
					color_to_use = GRAY
				case .NOTHING:
					sprite1 = get_sprite(1)
					color_to_use = DARKGRAY
				case .FLAG:
					sprite1 = get_sprite(2)
					color_to_use = GREEN
				case .NUMBER_HINT:
					sprite1 = get_sprite(int(tile.number_hint) + 4)
					color_to_use = RED
				case .REVEAL_BOMB:
					sprite1 = get_sprite(3)
					color_to_use = DARKPURPLE
				case .BOMB_EXPLODED:
					sprite1 = get_sprite(4)
					color_to_use = YELLOW
				}

								DrawTexturePro(sprite, sprite1, tile.rect, Vector2{0, 0}, 0, WHITE)
							}
		}
		EndDrawing()

				game_clock += GetFrameTime()
		free_all(context.temp_allocator)

	}

}

