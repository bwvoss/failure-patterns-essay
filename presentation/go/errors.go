package main

import (
	"fmt"
	"io/ioutil"
	"net/http"
)

func main() {
	client := http.Client{}
	response, err := client.Get("http://google.io")

	if err != nil {
		fmt.Println(err)
		return
	}

	contents, err := ioutil.ReadAll(response.Body)
	fmt.Println(string(contents))
}
