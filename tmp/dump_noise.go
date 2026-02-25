package main

import (
	"encoding/json"
	"fmt"
	"reflect"
	hiddify "github.com/sagernet/wireguard-go/hiddify"
)

func main() {
	t := reflect.TypeOf(hiddify.NoiseOptions{})
	fmt.Printf("type %s struct {\n", t.Name())
	for i := 0; i < t.NumField(); i++ {
		field := t.Field(i)
		fmt.Printf("\t%s %s `json:\"%s\"`\n", field.Name, field.Type.Name(), field.Tag.Get("json"))
	}
	fmt.Println("}")
}
