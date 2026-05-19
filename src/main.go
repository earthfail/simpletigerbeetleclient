package main

import (
	"fmt"
	"log"
	"os"

	. "github.com/tigerbeetle/tigerbeetle-go"
)

func main() {
	tbAddress := os.Getenv("TB_ADDRESS")
	if len(tbAddress) == 0 {
		tbAddress = "3000"
	}
	fmt.Printf("using tigerbeetle address: %v\n", tbAddress)

	client, err := NewClient(ToUint128(0), []string{tbAddress})
	if err != nil {
		log.Fatalf("Error creating client: %s", err)
	}
	defer client.Close()

	fmt.Println("Using tigerbeetle go client ^_^")
	defer fmt.Println("Go client went boom! or just stopped")
	if true {
		accountResults, err := client.CreateAccounts([]Account{
			{
				ID:          ID(),
				UserData128: ToUint128(0),
				UserData64:  0,
				UserData32:  0,
				Ledger:      1,
				Code:        718,
				Flags:       0,
				Timestamp:   0,
			},
			{
				ID:     ToUint128(102),
				Ledger: 1,
				Code:   718,
				Flags:  0,
			},
			{
				ID:     ToUint128(100),
				Ledger: 1,
				Code:   718,
				Flags: AccountFlags{
					Linked:                     true,
					DebitsMustNotExceedCredits: true,
				}.ToUint16(),
				// Flags: AccountFlags{
				// 	DebitsMustNotExceedCredits: true,
				// 	Linked:                     true,
				// }.ToUint16(),
			},
		})
		if err != nil {
			log.Printf("Couldn't create account: %v", err)
		}
		for i, result := range accountResults {
			switch result.Status {
			case AccountCreated:
				log.Printf("account %d successfully created with timestamp %d", i, result.Timestamp)
			case AccountExists:
				log.Printf("Batch account at %d already exists with timestamp %d.", i, result.Timestamp)
			default:
				log.Printf("Batch account at %d failed to create: %s", i, result.Status)
			}

		}
	}

	if false {
		accountResult, err := client.LookupAccounts([]Uint128{
			ToUint128(1779044466606833432),
		})
		if err != nil {
			log.Printf("Couldn't lookup accounts: %v", err)
		}
		for akey, ares := range accountResult {
			log.Printf("lookup res: %v -> %v", akey, ares)
			log.Printf("Hi there is there anyone here")
		}
	}
}
