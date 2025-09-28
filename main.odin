package campominado

import "core:fmt"
import "core:math/rand"
import "core:mem"
import vmem "core:mem/virtual"
import "core:time"
import rl "vendor:raylib"

should_game_run := true


SCREEN_DIM :: 800

TileState :: enum {
	UNDISCOVERED = 0,
	NOTHING = 1,
	FLAG = 2,
	REVEAL_BOMB = 3,
	BOMB_EXPLODED = 4,
	NUMBER_HINT, // 4+min=5..=4+max=12 , min 1 max 8
	HINT = 13,
}

BoardTile :: struct {
	using rect:  rl.Rectangle,
	state:       TileState,
	number_hint: u8,
	bomb:        bool,
}


BOARD_SIZE :: 30
NUMBER_OF_BOMBS :: 60

scatter_bombs :: proc(board: ^[BOARD_SIZE][BOARD_SIZE]BoardTile) {
	bomb_place: map[[2]int]u8
	defer delete(bomb_place)
	i := 0
	for {
		if i == NUMBER_OF_BOMBS {
			break
		}
		x := cast(int)rand.float32_range(0, BOARD_SIZE)
		y := cast(int)rand.float32_range(0, BOARD_SIZE)
		coord := [2]int{x, y}
		_entry, exists := &bomb_place[coord]
		if exists {continue}
		tile := &board[x][y]
		tile.bomb = true
		map_insert(&bomb_place, coord, 0)
		i += 1
	}
}
TILE_WIDTH :: SCREEN_DIM / BOARD_SIZE

make_board :: proc() -> [BOARD_SIZE][BOARD_SIZE]BoardTile {
	tile_width := TILE_WIDTH
	tile_height := tile_width
	board: [BOARD_SIZE][BOARD_SIZE]BoardTile
	for &row, x in board {
		for &tile, y in row {
			tile.state = .UNDISCOVERED
			tile.x = f32(x * tile_width)
			tile.y = f32(y * tile_height)
			tile.width = f32(tile_width)
			tile.height = f32(tile_height)
		}
	}
	return board

}

// 8 Neightboors from x,y 
neightboors_3x3 :: proc(
	x, y: int,
	x_size: int = BOARD_SIZE,
	y_size: int = BOARD_SIZE,
	allocator: mem.Allocator = context.allocator,
) -> [dynamic][2]int {
	out := make_dynamic_array([dynamic][2]int, allocator)
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

verify_flags :: proc(board: ^[BOARD_SIZE][BOARD_SIZE]BoardTile) -> bool {
	count := 0
	for &row in board {
		for &tile in row {
			if tile.state == .FLAG {count += 1}
		}
	}
	return count == NUMBER_OF_BOMBS
}
hint :: proc(board: ^[BOARD_SIZE][BOARD_SIZE]BoardTile, x, y: int) {
	arena: vmem.Arena
	arena_err := vmem.arena_init_static(&arena)
	ensure(arena_err == nil)
	arena_alloc := vmem.arena_allocator(&arena)
	defer {vmem.arena_destroy(&arena);free_all(context.temp_allocator)}
	checked: [BOARD_SIZE][BOARD_SIZE]bool = false
	center_tile := &board[x][y]
	neightboors := neightboors_3x3(x, y, allocator = arena_alloc)
	defer delete(neightboors)
	flags := 0
	tile_with_undiscoverd: [dynamic][2]int
	defer delete(tile_with_undiscoverd)
	for &i in neightboors {
		tile := &board[i.x][i.y]
		if tile.state == .UNDISCOVERED {
			tile.state = .HINT
			append(&tile_with_undiscoverd, [2]int{i.x, i.y})
		}
		if tile.state == .FLAG {
			flags += 1
		}
	}
	if flags == int(center_tile.number_hint) {
		for &i in tile_with_undiscoverd {
			fmt.println("reveal from hint", i.x, i.y)
			reveal(board, i.x, i.y)
		}
	}
}

reveal :: proc(board: ^[BOARD_SIZE][BOARD_SIZE]BoardTile, x, y: int) {
	arena: vmem.Arena
	arena_err := vmem.arena_init_static(&arena)
	ensure(arena_err == nil)
	arena_alloc := vmem.arena_allocator(&arena)
	defer {vmem.arena_destroy(&arena);free_all(context.temp_allocator)}
	checked: [BOARD_SIZE][BOARD_SIZE]bool = false


	map_tile_with_nothing: map[[2]int]u8
	defer delete(map_tile_with_nothing)

	center_tile := &board[x][y]
	if center_tile.state == .UNDISCOVERED && center_tile.number_hint == 0 {
		continue_discovering := true

		tile_with_nothing: [dynamic][2]int
		defer delete(tile_with_nothing)
		reserve(&tile_with_nothing, 6)
		map_insert(&map_tile_with_nothing, [2]int{x, y}, 0)
		append(&tile_with_nothing, [2]int{x, y})

		for continue_discovering {
			for len(tile_with_nothing) > 0 {
				val := pop_front(&tile_with_nothing)
				neightboors := neightboors_3x3(val.x, val.y, allocator = arena_alloc)
				defer delete(neightboors)
				for &i in neightboors {
					tile := &board[i.x][i.y]
					_entry, exists := &map_tile_with_nothing[i]
					// não precisa checar bomb,pois number_hint fica sempre a borda de uma
					if tile.state == .UNDISCOVERED && !exists && tile.number_hint == 0 {
						append(&tile_with_nothing, [2]int{i.x, i.y})
						map_insert(&map_tile_with_nothing, [2]int{i.x, i.y}, 0)
					}
				}
			}
			if len(tile_with_nothing) == 0 {continue_discovering = false}

		}
		map_alread_passed: map[[2]int]u8
		defer delete(map_alread_passed)
		for key in &map_tile_with_nothing {
			tile := &board[key.x][key.y]
			tile.state = .NOTHING
			append(&tile_with_nothing, key)
		}

		for &pos in tile_with_nothing {
			_entry, exists := &map_alread_passed[pos]
			neightboors := neightboors_3x3(pos.x, pos.y, allocator = arena_alloc)
			for &i in neightboors {
				tile := &board[i.x][i.y]
				if tile.number_hint > 0 {
					tile.state = .NUMBER_HINT
				}
			}
		}
	} else if center_tile.number_hint > 0 {
		center_tile.state = .NUMBER_HINT
	}
}

set_number_hint :: proc(board: ^[BOARD_SIZE][BOARD_SIZE]BoardTile) {
	for &row, x in board {
		for &tile, y in board {
			bomb_count: u8 = 0
			neighboors := neightboors_3x3(x, y)
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
SPRITE_TOTAL :: SPRITE_TOTAL_X * SPRITE_TOTAL_Y

gen_sprite_rectangle :: proc() -> (arr: [SPRITE_TOTAL]rl.Rectangle) {
	get_sprite :: proc(pos: int) -> rl.Rectangle {
		using rl
		frameRec: Rectangle = Rectangle{0, 0, SPRITE_DIM, SPRITE_DIM}
		x := pos % SPRITE_TOTAL_X
		y := pos / SPRITE_TOTAL_X
		frameRec.x = f32(x * SPRITE_DIM + x)
		frameRec.y = f32(y * SPRITE_DIM + y)
		return frameRec
	}
	for i in 0 ..< SPRITE_TOTAL {
		arr[i] = get_sprite(i)
	}
	return arr
}
sprite_file := #load("./tile_sprite.png")
prepare_image :: proc() -> rl.Texture2D {
	image: rl.Image = rl.LoadImageFromMemory(".PNG", &sprite_file[0], i32(len(sprite_file)))
	defer rl.UnloadImage(image)
	return rl.LoadTextureFromImage(image)
}

main :: proc() {
	when ODIN_DEBUG {
		track: mem.Tracking_Allocator
		mem.tracking_allocator_init(&track, context.allocator)
		context.allocator = mem.tracking_allocator(&track)

		defer {
			if len(track.allocation_map) > 0 {
				fmt.eprintf("=== %v allocations not freed: ===\n", len(track.allocation_map))
				for _, entry in track.allocation_map {
					fmt.eprintf("- %v bytes @ %v\n", entry.size, entry.location)
				}
			}
			mem.tracking_allocator_destroy(&track)
		}
	}
	using rl

	SetConfigFlags({.VSYNC_HINT})
	InitWindow(SCREEN_DIM, SCREEN_DIM, "Campo Minado")
	SetTargetFPS(60)
	defer CloseWindow()
	sprite: Texture2D = prepare_image()
	sprite_rectangle := gen_sprite_rectangle()
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
	flags := 0
	for should_game_run {
		defer mouse_event.state = .EMPTY
		// Esc or CloseWindowIcon
		if WindowShouldClose() {should_game_run = false}
		if (flags == NUMBER_OF_BOMBS) && (verify_flags(&board)) {
			should_game_run = false
			fmt.println("you win")
			time.sleep(10 * time.Second)
		}

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

			#partial switch state^ {
			case .TRIGGER:
				if tile.bomb {
					should_game_run = false
					fmt.println("you lose")
					tile.state = .BOMB_EXPLODED
				} else {
					reveal(&board, x, y)
				}
			case .FLAG:
				if tile.state == .FLAG {
					tile.state = .UNDISCOVERED
				} else if tile.state == .UNDISCOVERED {tile.state = .FLAG;flags += 1}
			case .HOLD:
				hint(&board, x, y)
			}
			fmt.println(flags, NUMBER_OF_BOMBS)

		}
		//drawing

		BeginDrawing()
		for &row, x in board {
			for &tile, y in row {
				color_to_use: rl.Color

				sprite1: ^Rectangle

				switch tile.state {
				case .UNDISCOVERED:
					sprite1 = &sprite_rectangle[0]
				case .NOTHING:
					sprite1 = &sprite_rectangle[1]
				case .FLAG:
					sprite1 = &sprite_rectangle[2]
				case .NUMBER_HINT:
					sprite1 = &sprite_rectangle[int(tile.number_hint) + 4]
				case .REVEAL_BOMB:
					sprite1 = &sprite_rectangle[3]
				case .BOMB_EXPLODED:
					sprite1 = &sprite_rectangle[4]
				case .HINT:
					sprite1 = &sprite_rectangle[TileState.HINT]
					tile.state = .UNDISCOVERED
				}

				DrawTexturePro(sprite, sprite1^, tile.rect, Vector2{0, 0}, 0, WHITE)
			}
		}
		EndDrawing()

		free_all(context.temp_allocator)
	}

}

