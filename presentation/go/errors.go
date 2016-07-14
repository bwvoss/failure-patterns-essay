package main

import (
	"fmt"
	"io/ioutil"
	"net/http"
)

func main() {
	client := http.Client{
		Timeout: 1,
	}
	response, err := client.Get("http://blah.lskdfj")

	if err != nil {
		fmt.Println(err)
		return
	}

	contents, err := ioutil.ReadAll(response.Body)
	fmt.Println(string(contents))
}
