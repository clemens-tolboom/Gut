extends "res://scripts/gut.gd".Test


func test_count_to_1000000():
	for i in range(1000000):
		pass
	gut.assert_true(true)

func test_count_to_2000000():
	for i in range(2000000):
		pass
	gut.assert_true(true)

func test_count_to_3000000():
	for i in range(3000000):
		pass
	gut.assert_true(true)


