(ns app.core
    (:require-macros
      [cljs.core.async.macros :as asyncm :refer (go go-loop)])
    (:require [reagent.core :as reagent :refer [atom]]
              [clojure.string :as str]
              [ajax.core :as ajx]
              [cljs.core.async :as async :refer (<! >! put! chan close!)]
              [wscljs.client :as ws]
              [wscljs.format :as fmt]))

(enable-console-print!)
(println "Console ready")

(def wsurl "ws://localhost:8080/ws/")

(defonce question (atom "..."))
(defonce answer (atom "-"))
(defonce current-team (atom nil))

(defonce socket (atom nil))
(defonce ping-timer (atom nil))

;; Handler stuff

(defn decode-html [h]
  (let* [txt (. js/document createElement "textarea")]
    (do (set! (.-innerHTML txt) h)
        (.-value txt))))

(defn shuffle-answers [question-type answers]
  (cond
   (= question-type "boolean") (sort answers)
   :else (->> answers shuffle shuffle)))

(defn on-question [q-spec]
  (let* [q (->> q-spec .-question)
         correct-answer (->> q-spec .-correct_answer)
         incorrect-answers (->> q-spec .-incorrect_answers)
         answers (shuffle-answers
                  (.-type q-spec)
                  (conj (js->clj incorrect-answers) correct-answer))]
    (do
     ;(. js/console (log "question " q "answers " answers))
     (reset! question (->> q decode-html)) 
     (reset! answer
             (map-indexed
              (fn [i a] [:div {:key i}
                         (str (inc i) ". ")
                         (decode-html a)])
              answers)))))

(defn on-message [e]
  (let* [e-data (.parse js/JSON (.-data e))
         e-type (.-type e-data)]
    (do
     ;(if-not (= e-type "pong") (. js/console (log "on-message:" e e-type e-data)))
     (cond
      (= e-type "pong") nil ; no-op
      (= e-type "question") (on-question (.-question e-data))
      (= e-type "buzz") (reset! current-team (.-team e-data))
      (= e-type "clear") (reset! current-team nil)
      :else (. js/console (log "unexpected type:" e-type))))))

(defn on-open [e]
  (do
   (. js/console (log "Opening a new connection:" e))
   (let* [ping-fn (fn [] (ws/send @socket "ping"))]
     (reset! ping-timer (js/setInterval ping-fn 5000)))))

(defn on-close [e]
  (do
   (. js/console (log "Closing a connection:" e))
   (js/clearInterval @ping-timer)
   (reset! ping-timer nil)))

(def handlers {:on-message #(on-message %1)
               :on-open    #(on-open %1)
               :on-close   #(on-close %1)})

;; Connection

(defn socket-swap [old-socket new-socket]
  (do (if-not (= old-socket nil) (ws/close old-socket))
      new-socket))

;; React things

(defn app []
  [:div.center
    [:h3.question-marker "Q: " [:span.question @question]]
    [:h3.question-marker "A: " [:span.question @answer]]
    (if-not (= @current-team nil) [:h1 "Team: " @current-team])])

;; Press play!

(swap! socket socket-swap (ws/create wsurl handlers))
(reagent/render-component [app] (. js/document (getElementById "app")))

;;
;; Figwheel(?) meta stuff
;;

;(defn on-js-reload [] (js/clearInterval @ping-timer))

