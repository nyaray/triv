(ns app.core
    (:require [reagent.core :as reagent :refer [atom]]
              [clojure.string :as str]
              [wscljs.client :as ws]
              [wscljs.format :as fmt]))

(enable-console-print!)
(println "Console ready")

(def wsurl "ws://localhost:8080/ws/")

(defonce current-question (atom "..."))
(defonce current-answer (atom "-"))
(defonce current-team (atom nil))
(defonce current-duds (atom []))

(defonce socket (atom nil))
(defonce ping-timer (atom nil))

;; Handler stuff

(defn decode-html [h]
  (let* [txt (. js/document createElement "textarea")]
    (do
     (set! (.-innerHTML txt) h)
     (.-value txt))))

(defn order-answers [question-type answers]
  (cond
   (= question-type "boolean") (sort answers)
   :else (->> answers shuffle shuffle)))

(defn on-question [{:keys [type :as qt question correct_answer incorrect_answers]}]
  (let* [answers (order-answers qt (conj incorrect_answers correct_answer))
         answer-fn (fn [i a] [:div {:key i}
                              (str (inc i) ". ")
                              (decode-html a)])]
    (reset! current-question (->> question decode-html))
    (reset! current-answer (map-indexed answer-fn answers))))

(defn parse-message-data [e]
 (->> e
      (.-data)
      (.parse js/JSON)
      (#(js->clj % :keywordize-keys true))))

(defn on-message [e]
  (let*
    [data (parse-message-data e)
     e-type (:type data)]
    ;(if-not (= e-type "pong") (prn "data" data))
    (cond
     (= e-type "pong") nil ; no-op
     (= e-type "question") (if-not (= (:question data) nil) (on-question (:question data)))
     (= e-type "buzz") (reset! current-team (:team data))
     (= e-type "duds") (reset! current-duds (:duds data))
     (= e-type "clear") (do (reset! current-team nil)
                            (reset! current-duds []))
     :else (.log  js/console "unexpected type:" e-type))))

(defn on-open [e]
  (do
   (.log js/console "Opening a new connection:" e)
   (let* [ping-fn (fn [] (ws/send @socket "ping"))]
     (reset! ping-timer (js/setInterval ping-fn 5000)))))

(defn on-close [e]
  (do
   (.log js/console "Closing a connection:" e)
   (js/clearInterval @ping-timer)
   (reset! ping-timer nil)))

(def handlers {:on-message #(on-message %1)
               :on-open #(on-open %1)
               :on-close #(on-close %1)})

;; Connection

(defn socket-swap [old-socket new-socket]
  (do (if-not (= old-socket nil) (ws/close old-socket))
      new-socket))

;; React things

(defn app []
  [:div.center
   [:h3.question-marker "Q: " [:span.question @current-question]]
   [:h3.question-marker "A: " [:span.question @current-answer]]
   (if-not (= @current-team nil) [:h1 "Team: " @current-team])
   (if-not (= @current-duds [])
     [:h1 "Duds: " (map-indexed (fn [i d] [:div {:key i} d]) @current-duds)])])

;; Press play!

(swap! socket socket-swap (ws/create wsurl handlers))
(reagent/render-component [app] (. js/document (getElementById "app")))

;;
;; Figwheel(?) meta stuff
;;

;(defn on-js-reload [] (js/clearInterval @ping-timer))

