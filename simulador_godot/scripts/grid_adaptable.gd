class_name GridAdaptable
extends GridContainer
## Rejilla con tantas columnas como quepan de min_px de ancho (grid-template-columns: repeat(auto-fill, minmax(min_px, 1fr))
## de la web). Los hijos se estiran para repartirse el ancho.

var min_px := 230.0

func _notification(que: int) -> void:
	if que == NOTIFICATION_RESIZED or que == NOTIFICATION_SORT_CHILDREN:
		var sep := get_theme_constant("h_separation")
		var n := maxi(1, int((size.x + sep) / (min_px + sep)))
		if n != columns: columns = n
		for c in get_children():          # 1fr: cada columna se estira por igual
			if c is Control: (c as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
